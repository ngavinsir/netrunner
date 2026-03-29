(ns game.parity.oracle
  (:import
   [java.net StandardProtocolFamily UnixDomainSocketAddress]
   [java.nio.channels Channels ServerSocketChannel]
   [java.nio.charset StandardCharsets]
   [java.nio.file Files Path Paths])
  (:require
   [cheshire.core :as json]
   [clojure.java.io :as io]
   [game.parity.export :as export]))

(defn request->bundle
  [{:keys [seed actions matchup]}]
  (export/replay-bundle-after-actions (or seed 1) (or actions []) matchup))

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
              response (json/generate-string (request->bundle request))]
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
                response (json/generate-string (request->bundle request))]
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
