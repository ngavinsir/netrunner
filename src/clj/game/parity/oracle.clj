(ns game.parity.oracle
  (:import
   [java.util UUID]
   [java.net StandardProtocolFamily UnixDomainSocketAddress]
   [java.nio.channels Channels ServerSocketChannel]
   [java.nio.charset StandardCharsets]
   [java.nio.file Files Path Paths])
  (:require
   [cheshire.core :as json]
   [clojure.java.io :as io]
   [game.parity.export :as export]))

(defonce ^:private sessions (atom {}))
(def ^:private request-lock (Object.))

(defn request->bundle
  [{:keys [seed actions matchup]}]
  (export/replay-bundle-after-actions (or seed 1) (or actions []) matchup))

(defn- session-state!
  [session-id]
  (or (get @sessions session-id)
      (throw (ex-info "Unknown oracle session" {:session-id session-id}))))

(defn- start-session!
  [{:keys [seed matchup]}]
  (let [session-id (str (UUID/randomUUID))
        state (export/replay-state (or seed 1) matchup)]
    (swap! sessions assoc session-id state)
    (assoc (export/canonical-bundle state) :session-id session-id)))

(defn- apply-session-action!
  [{:keys [session-id action]}]
  (let [state (session-state! session-id)]
    (export/advance-replay-state! state action)
    (assoc (export/canonical-bundle state) :session-id session-id)))

(defn- close-session!
  [{:keys [session-id]}]
  (swap! sessions dissoc session-id)
  {:ok true})

(defn- handle-request
  [request]
  (case (:op request)
    "start-session" (start-session! request)
    "apply-action" (apply-session-action! request)
    "close-session" (close-session! request)
    (request->bundle request)))

(defn read-request
  [path]
  (-> (slurp (io/file path))
      (json/parse-string true)))

(defn write-response
  [response]
  (println (json/generate-string response {:pretty true})))

(defn serve-stdio!
  []
  (with-open [reader (io/reader *in*)
              writer (io/writer *out*)]
    (loop []
      (when-let [line (.readLine reader)]
        (let [request (json/parse-string line true)
              response (locking request-lock
                         (json/generate-string (handle-request request)))]
          (.write writer response)
          (.write writer "\n")
          (.flush writer))
        (recur)))))

(defn- handle-socket-client!
  [socket]
  (future
    (try
      (with-open [socket socket
                  reader (-> socket
                             Channels/newInputStream
                             (io/reader :encoding "UTF-8"))
                  writer (-> socket
                             Channels/newOutputStream
                             (io/writer :encoding "UTF-8"))]
        (when-let [line (.readLine reader)]
          (let [request (json/parse-string line true)
                response (locking request-lock
                           (json/generate-string (handle-request request)))]
            (.write writer response)
            (.write writer "\n")
            (.flush writer))))
      (catch Exception e
        (binding [*out* *err*]
          (println (str "ORACLE ERROR: " (.getMessage e)))
          (.printStackTrace e *err*))))))

(defn serve-unix!
  [socket-path]
  (let [path (Paths/get socket-path (make-array String 0))]
    (Files/deleteIfExists path)
    (with-open [server (doto (ServerSocketChannel/open StandardProtocolFamily/UNIX)
                         (.bind (UnixDomainSocketAddress/of ^Path path)))]
      (try
        (loop []
          (when-let [socket (.accept server)]
            (handle-socket-client! socket)
            (recur)))
        (finally
          (Files/deleteIfExists path))))))

(defn -main
  [& args]
  (let [[mode value] args]
    (cond
      (= "--stdio" mode)
      (serve-stdio!)

      (= "--unix-server" mode)
      (do
        (when-not value
          (throw (ex-info "Expected unix socket path" {})))
        (serve-unix! value))

      :else
      (do
        (when-not mode
          (throw (ex-info "Expected request JSON path" {})))
        (-> mode
            read-request
            request->bundle
            write-response)))))
