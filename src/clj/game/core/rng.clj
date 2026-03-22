(ns game.core.rng
  (:import [java.security SecureRandom]))

(def ^:private splitmix-gamma (unchecked-long 0x9E3779B97F4A7C15N))
(def ^:private splitmix-mul-1 (unchecked-long 0xBF58476D1CE4E5B9N))
(def ^:private splitmix-mul-2 (unchecked-long 0x94D049BB133111EBN))

(defonce ^:private fallback-rng
  ;; Used only when no deterministic seed is configured on the game state.
  (let [rand (SecureRandom.)
        seed-bytes (byte-array 128)]
    (.nextBytes (SecureRandom.) seed-bytes)
    (.setSeed rand seed-bytes)
    rand))

(defn secure-seed
  "Returns a securely generated 64-bit seed for deterministic game RNG."
  []
  (.nextLong (SecureRandom.)))

(defn- next-word
  [^long seed]
  (let [seed' (unchecked-add seed splitmix-gamma)
        z1 (unchecked-multiply (bit-xor seed' (unsigned-bit-shift-right seed' 30)) splitmix-mul-1)
        z2 (unchecked-multiply (bit-xor z1 (unsigned-bit-shift-right z1 27)) splitmix-mul-2)
        z3 (bit-xor z2 (unsigned-bit-shift-right z2 31))]
    [seed' z3]))

(defn rand-int-seeded
  "Pure deterministic random int in [0, n) plus next seed."
  [^long seed n]
  (when-not (pos? n)
    (throw (ex-info "rand-int-seeded requires positive n" {:n n})))
  (let [[seed' word] (next-word seed)]
    [seed' (int (Long/remainderUnsigned word (long n)))]))

(defn rand-nth-seeded
  "Pure deterministic nth-choice plus next seed."
  [^long seed coll]
  (let [v (vec coll)]
    (when (empty? v)
      (throw (ex-info "rand-nth-seeded requires a non-empty collection" {})))
    (let [[seed' idx] (rand-int-seeded seed (count v))]
      [seed' (nth v idx)])))

(defn shuffle-coll-seeded
  "Pure deterministic Fisher-Yates shuffle plus next seed."
  [^long seed coll]
  (loop [seed seed
         v (vec coll)
         i (dec (count coll))]
    (if (<= i 0)
      [seed v]
      (let [[seed' j] (rand-int-seeded seed (inc i))
            vi (nth v i)
            vj (nth v j)
            v' (if (= i j)
                 v
                 (assoc v i vj j vi))]
        (recur seed' v' (dec i))))))

(defn seeded-state?
  [state]
  (some? (:rng-seed @state)))

(defn rand-int!
  "Deterministic when the game state has :rng-seed, otherwise falls back to host randomness."
  [state n]
  (if-let [seed (:rng-seed @state)]
    (let [[seed' value] (rand-int-seeded seed n)]
      (swap! state assoc :rng-seed seed')
      value)
    (clojure.core/rand-int n)))

(defn rand-nth!
  "Deterministic when the game state has :rng-seed, otherwise falls back to host randomness."
  [state coll]
  (if-let [seed (:rng-seed @state)]
    (let [[seed' value] (rand-nth-seeded seed coll)]
      (swap! state assoc :rng-seed seed')
      value)
    (clojure.core/rand-nth (vec coll))))

(defn shuffle-coll!
  "Deterministic when the game state has :rng-seed, otherwise falls back to SecureRandom-backed shuffle."
  [state coll]
  (if-let [seed (:rng-seed @state)]
    (let [[seed' shuffled] (shuffle-coll-seeded seed coll)]
      (swap! state assoc :rng-seed seed')
      shuffled)
    (let [al (java.util.ArrayList. coll)]
      (java.util.Collections/shuffle al fallback-rng)
      (clojure.lang.RT/vector (.toArray al)))))
