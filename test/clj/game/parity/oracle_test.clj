(ns game.parity.oracle-test
  (:require
   [clojure.test :refer [deftest is testing]]
   [game.parity.export :as export]
   [game.parity.oracle :as oracle]))

(deftest request-interface-replays-arbitrary-action-sequences
  (let [request {:seed 1
                 :actions [{:kind :prompt-choice
                            :side :corp
                            :choice {:choice-type :string
                                     :value "Keep"}}
                           {:kind :prompt-choice
                            :side :runner
                            :choice {:choice-type :string
                                     :value "Keep"}}]}]
    (testing "the generic oracle interface matches the existing scenario result"
      (is (= (export/bundle-after-actions 1 (:actions request))
             (oracle/request->bundle request))))))
