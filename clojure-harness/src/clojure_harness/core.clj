(ns clojure-harness.core
  (:require [clojure.java.jdbc :as jdbc]
            [yesql.core])
  (:gen-class))

(defn db-cnxn [path] {:connection (jdbc/get-connection (str "sqlite:" path))})

(yesql.core/defqueries "sql/schema.sql")
(yesql.core/defqueries "sql/fdl.sql")

(def perm-schema [create-vertices! create-vcollapse! create-edges! create-positions!])
(def temp-schema [create-boolean-choice! create-inflight-positions! create-quadtree! create-repulsions! create-attractions! create-forces!])
(def schema (concat perm-schema temp-schema))

(defn init-db! [cnxn]
  (dorun (map #(% cnxn) schema)))
(defn import-from-raw! [cnxn]
  (raw-edges-to-degree-ordered-vertices! cnxn)
  (raw-edges-to-edges! cnxn)
  nil)

(defn collapse-levels! [cnxn m starting-level & {:keys [iter-printf] :or {iter-printf nil}}]
  (loop [level starting-level]
    (if (not (zero? (:collapse_more (first (should-collapse-more cnxn m level)))))
      (do
        (vcollapse! cnxn level m)
        (collapse-edges! cnxn level)
        (if iter-printf (iter-printf cnxn))
        (recur (+ 1 level))))))

(defn get-graph-energy [cnxn] (:graph_energy (first (graph-energy cnxn))))

(defn update-positions! [cnxn c k Ө level tol init-step step-mul & {:keys [iter-printf] :or {iter-printf nil}}]
  (loop [level level
         energy Double/POSITIVE_INFINITY
         step init-step]
    (make-quadtree! cnxn)
    (make-repulsions! cnxn c k Ө)
    (make-attractions! cnxn k level)
    (make-forces! cnxn)
    (let [not-converged? (zero? (:is_converged (first (is-converged cnxn step k tol))))]
      (if not-converged?
        (do (replace-inflight-positions! cnxn step)
            (if iter-printf (iter-printf cnxn))
            (delete-repulsions! cnxn)
            (delete-attractions! cnxn)
            (delete-quadtree! cnxn)
            (let [energy' (get-graph-energy cnxn)]
              (delete-forces! cnxn)
              (if (= energy energy') (rerandomize-inflight-positions! cnxn))
              (recur level energy' (if (< energy' energy) (min (Math/sqrt init-step) (/ step step-mul)) init-step)) ))
        (do (land-positions! cnxn level)
            (add-next-positions! cnxn (- level 1))
            (delete-repulsions! cnxn)
            (delete-attractions! cnxn)
            (delete-forces! cnxn)
            (delete-quadtree! cnxn)
            (if (pos? level) (recur (- level 1) 0 init-step)))))))

(defn -main
  "I don't do a whole lot ... yet."
  [& args]
  (println "Hello, World!"))
