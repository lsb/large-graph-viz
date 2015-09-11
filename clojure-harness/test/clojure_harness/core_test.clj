(ns clojure-harness.core-test
  (:require [clojure.test :refer :all]
            [yesql.core]
            [clojure-harness.core :refer :all]))

(yesql.core/defqueries "sql/test.sql")

(deftest e2e-test
  (testing "Test whether an end-to-end fdl of an 32-node ring comes out looking like a ring"
    (let [c (db-cnxn ":memory:")
          levels 5
          node-count (reduce * (replicate levels 2))]
      (init-db! c)
      (create-raw-edges! c)
      (create-a-ring! c (- node-count 1))
      (import-from-raw! c)
      (collapse-levels! c 2 0)
      (randomize-nodes! c levels)
      (update-positions! c 0.2 1 500 levels 0.01 0.01 0.9)
      (is (> 6.0 (:stdev (first (angle-stdev c 0 node-count))))))))
