(ns game.parity.export-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [game.parity.export :as export]))

(deftest beginner-init-fixture-is-deterministic
  (testing "same seed yields the same exported beginner fixture"
    (is (= (export/beginner-init-fixture 4242)
           (export/beginner-init-fixture 4242)))))

(deftest beginner-init-fixture-has-expected-shape
  (let [fixture (export/beginner-init-fixture 7)
        initial (:initial fixture)
        actions (:legal-actions initial)
        choices (set (map #(get-in % [:choice :value]) actions))]
    (testing "top-level metadata is present"
      (is (= 1 (:fixture-version fixture)))
      (is (= :initial-state (:fixture-kind fixture)))
      (is (= :system-gateway-beginner (:matchup fixture)))
      (is (= 7 (:seed fixture))))
    (testing "initial decision is the corp mulligan prompt"
      (is (= :corp (:decision-side initial)))
      (is (= #{"Keep" "Mulligan"} choices)))
    (testing "first-step transitions are exported for the current legal actions"
      (is (= 2 (count (:transitions fixture))))
      (is (every? :result (:transitions fixture))))
    (testing "second-step runner mulligan transitions are exported"
      (is (every? #(= 2 (count (:transitions %))) (:transitions fixture)))
      (is (every? (fn [transition]
                    (= :runner (get-in transition [:result :decision-side])))
                  (:transitions fixture))))
    (testing "third-step opening transitions are exported after runner mulligan choices"
      (is (every? (fn [corp-transition]
                    (every? #(contains? % :transitions) (:transitions corp-transition)))
                  (:transitions fixture)))
      (is (every? (fn [corp-transition]
                    (every? #(seq (:transitions %)) (:transitions corp-transition)))
                  (:transitions fixture))))))
