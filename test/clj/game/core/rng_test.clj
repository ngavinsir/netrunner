(ns game.core.rng-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [game.core.rng :as rng]))

(deftest seeded-shuffle-is-deterministic
  (testing "same seed yields same shuffled collection and next seed"
    (let [[seed-a shuffled-a] (rng/shuffle-coll-seeded 123456789 [1 2 3 4 5 6])
          [seed-b shuffled-b] (rng/shuffle-coll-seeded 123456789 [1 2 3 4 5 6])]
      (is (= seed-a seed-b))
      (is (= shuffled-a shuffled-b)))))

(deftest stateful-shuffle-advances-seed-deterministically
  (testing "stateful seeded shuffle updates :rng-seed predictably"
    (let [state-a (atom {:rng-seed 42})
          state-b (atom {:rng-seed 42})
          shuffled-a (rng/shuffle-coll! state-a [:a :b :c :d :e])
          shuffled-b (rng/shuffle-coll! state-b [:a :b :c :d :e])]
      (is (= shuffled-a shuffled-b))
      (is (= (:rng-seed @state-a) (:rng-seed @state-b)))
      (is (not= 42 (:rng-seed @state-a))))))

(deftest seeded-rand-int-is-deterministic
  (testing "same seed yields same bounded random int and next seed"
    (let [[seed-a value-a] (rng/rand-int-seeded 99 10)
          [seed-b value-b] (rng/rand-int-seeded 99 10)]
      (is (= seed-a seed-b))
      (is (= value-a value-b))
      (is (<= 0 value-a 9)))))
