(ns game.parity.export
  (:require
   [cheshire.core :as json]
   [clojure.edn :as edn]
   [clojure.java.io :as io]
   [clojure.string :as string]
   [game.core.diffs :as diffs]
   [game.main :as main]
   [game.core.set-up :as set-up]
   [jinteki.cards :refer [all-cards]]
   [jinteki.preconstructed :as preconstructed]
   [jinteki.utils :refer [other-side]]))

(def ^:private card-namespaces
  '[game.cards.agendas
    game.cards.assets
    game.cards.basic
    game.cards.events
    game.cards.hardware
    game.cards.ice
    game.cards.identities
    game.cards.operations
    game.cards.programs
    game.cards.resources
    game.cards.upgrades])

(defonce ^:private card-defs-loaded? (atom false))

(def ^:private default-export-path
  "test/resources/parity/system-gateway-beginner-init.json")

(defn- select-non-nil-keys
  [m ks]
  (reduce (fn [acc k]
            (let [v (get m k ::missing)]
              (if (or (= ::missing v) (nil? v))
                acc
                (assoc acc k v))))
          {}
          ks))

(defn- kw->segment
  [x]
  (cond
    (keyword? x) (name x)
    :else x))

(defn- segment->path-key
  [x]
  (cond
    (string? x) (keyword x)
    :else x))

(defn- locator
  [path]
  (mapv kw->segment path))

(defn- ensure-card-defs-loaded!
  []
  (when-not @card-defs-loaded?
    (when (empty? @all-cards)
      (->> (io/file "data/cards.edn")
           slurp
           edn/read-string
           (map (juxt :title identity))
           (into {})
           (reset! all-cards)))
    (doseq [ns-sym card-namespaces]
      (require ns-sym))
    (reset! card-defs-loaded? true)))

(defn- minimal-card
  [side title]
  {:side side
   :title title})

(defn- resolve-card-def
  [side card]
  (let [title (cond
                (string? card) card
                (map? card) (:title card)
                :else (str card))
        fallback (cond
                   (string? card) (minimal-card side card)
                   (map? card) (merge {:side side} card)
                   :else (minimal-card side title))
        loaded (get @all-cards title)]
    (merge loaded fallback)))

(defn- prepare-precon-deck
  [side {:keys [identity cards]}]
  {:identity (merge (get @all-cards (:title identity))
                    (assoc identity :type "Identity"))
   :cards (mapv (fn [{:keys [qty card art]}]
                  {:qty qty
                   :art art
                   :card (resolve-card-def side card)})
                cards)})

(defn- register-beginner-cards!
  []
  (let [corp (prepare-precon-deck "Corp" preconstructed/gateway-beginner-corp)
        runner (prepare-precon-deck "Runner" preconstructed/gateway-beginner-runner)
        corp-cards (into {}
                         (map (fn [{:keys [card]}]
                                [(:title card) card]))
                         (:cards corp))
        runner-cards (into {}
                           (map (fn [{:keys [card]}]
                                  [(:title card) card]))
                           (:cards runner))
        identities {(:title (:identity corp)) (:identity corp)
                    (:title (:identity runner)) (:identity runner)}]
    (swap! all-cards merge identities corp-cards runner-cards)))

(defn beginner-game
  ([]
   (beginner-game 1))
  ([seed]
   (let [corp preconstructed/gateway-beginner-corp
         runner preconstructed/gateway-beginner-runner]
     {:gameid 1
      :format "system-gateway"
      :seed seed
      :players [{:side "Corp"
                 :user {:username "Corp"}
                 :deck (prepare-precon-deck "Corp" corp)}
                {:side "Runner"
                 :user {:username "Runner"}
                 :deck (prepare-precon-deck "Runner" runner)}]})))

(defn beginner-state
  ([]
   (beginner-state 1))
  ([seed]
   (ensure-card-defs-loaded!)
   (register-beginner-cards!)
   (set-up/init-game (beginner-game seed))))

(defn- register-intermediate-cards!
  []
  (let [corp (prepare-precon-deck "Corp" preconstructed/gateway-intermediate-corp)
        runner (prepare-precon-deck "Runner" preconstructed/gateway-intermediate-runner)
        corp-cards (into {}
                         (map (fn [{:keys [card]}]
                                [(:title card) card]))
                         (:cards corp))
        runner-cards (into {}
                           (map (fn [{:keys [card]}]
                                  [(:title card) card]))
                           (:cards runner))
        identities {(:title (:identity corp)) (:identity corp)
                    (:title (:identity runner)) (:identity runner)}]
    (swap! all-cards merge identities corp-cards runner-cards)))

(defn intermediate-game
  ([]
   (intermediate-game 1))
  ([seed]
   (let [corp preconstructed/gateway-intermediate-corp
         runner preconstructed/gateway-intermediate-runner]
     {:gameid 1
      :format "system-gateway"
      :seed seed
      :players [{:side "Corp"
                 :user {:username "Corp"}
                 :deck (prepare-precon-deck "Corp" corp)}
                {:side "Runner"
                 :user {:username "Runner"}
                 :deck (prepare-precon-deck "Runner" runner)}]})))

(defn intermediate-state
  ([]
   (intermediate-state 1))
  ([seed]
   (ensure-card-defs-loaded!)
   (register-intermediate-cards!)
   (set-up/init-game (intermediate-game seed))))

(defn- canonical-choice
  [choice]
  (cond
    (string? choice) {:choice-type :string
                      :value choice}
    (number? choice) {:choice-type :number
                      :value choice}
    (keyword? choice) {:choice-type :keyword
                       :value (name choice)}
    (map? choice) (let [value (:value choice)]
                    (cond
                      (map? value) {:choice-type :card
                                    :card (select-non-nil-keys value [:code :title :printed-title :side])}
                      (string? value) {:choice-type :string
                                       :value value}
                      (number? value) {:choice-type :number
                                       :value value}
                      (keyword? value) {:choice-type :keyword
                                        :value (name value)}
                      :else {:choice-type :value
                             :value value}))
    :else {:choice-type :value
           :value choice}))

(defn- canonical-ability
  [idx ability]
  (select-non-nil-keys
    {:index idx
     :label (:label ability)
     :cost-label (:cost-label ability)
     :msg (:msg ability)
     :playable (:playable ability)
     :dynamic (:dynamic ability)}
    [:index :label :cost-label :msg :playable :dynamic]))

(defn- canonical-subroutine
  [idx subroutine]
  (select-non-nil-keys
    {:index idx
     :label (:label subroutine)
     :msg (:msg subroutine)
     :broken (:broken subroutine)
     :fired (:fired subroutine)
     :resolve (:resolve subroutine)}
    [:index :label :msg :broken :fired :resolve]))

(declare canonical-card)

(defn- hide-only-prompt?
  [prompt]
  (and (= :select (:prompt-type prompt))
       (empty? (remove (fn [choice]
                         (or (= "Hide" choice)
                             (= "Hide" (:value choice))))
                       (:choices prompt)))))

(defn- filter-hide-choices
  [choices]
  (when (sequential? choices)
    (->> choices
         (remove (fn [choice]
                   (or (= "Hide" choice)
                       (= "Hide" (:value choice)))))
         vec)))

(defn- canonical-cards
  [cards path-prefix host-locator]
  (when (seq cards)
    (mapv (fn [idx card]
            (canonical-card card (conj path-prefix idx) host-locator))
          (range)
          cards)))

(defn- canonical-card
  [card path host-locator]
  (when card
    (let [loc (locator path)]
      (select-non-nil-keys
        {:locator loc
         :hosted-on host-locator
         :title (:title card)
         :printed-title (:printed-title card)
         :normalizedtitle (:normalizedtitle card)
         :code (:code card)
         :side (:side card)
         :type (:type card)
         :zone (some->> (:zone card) (mapv kw->segment))
         :rezzed (:rezzed card)
         :facedown (:facedown card)
         :face (:face card)
         :seen (:seen card)
         :installed (:installed card)
         :new (:new card)
         :disabled (:disabled card)
         :advance-counter (:advance-counter card)
         :extra-advance-counter (:extra-advance-counter card)
         :counter (:counter card)
         :cost (:cost card)
         :strength (:strength card)
         :current-strength (:current-strength card)
         :subtypes (:subtypes card)
         :playable (:playable card)
         :playable-as-if-in-hand (:playable-as-if-in-hand card)
         :flashback-playable (:flashback-playable card)
         :abilities (some->> (:abilities card)
                             (map-indexed canonical-ability)
                             not-empty)
         :corp-abilities (some->> (:corp-abilities card)
                                  (map-indexed canonical-ability)
                                  not-empty)
         :runner-abilities (some->> (:runner-abilities card)
                                    (map-indexed canonical-ability)
                                    not-empty)
         :subroutines (some->> (:subroutines card)
                               (map-indexed canonical-subroutine)
                               not-empty)
         :hosted (canonical-cards (:hosted card) (conj path :hosted) loc)}
        [:locator :hosted-on :title :printed-title :normalizedtitle :code :side :type :zone :rezzed
         :facedown :face :seen :installed :new :disabled :advance-counter :extra-advance-counter
         :counter :cost :strength :current-strength :subtypes :playable :playable-as-if-in-hand
         :flashback-playable :abilities :corp-abilities :runner-abilities :subroutines :hosted]))))

(defn- canonical-prompt
  [prompt]
  (when (and prompt
             (not (hide-only-prompt? prompt)))
    (let [choices (or (filter-hide-choices (:choices prompt))
                      (:choices prompt))]
    (select-non-nil-keys
      {:prompt-type (:prompt-type prompt)
       :source-card (some-> (:card prompt)
                            (select-non-nil-keys [:code :title :printed-title :side]))
       :choices (some->> choices
                         (mapv canonical-choice)
                         not-empty)
       :show-discard (:show-discard prompt)
       :show-opponent-discard (:show-opponent-discard prompt)
       :offer-bad-pub? (:offer-bad-pub? prompt)
       :player (:player prompt)
       :base (:base prompt)
       :bonus (:bonus prompt)
       :strength (:strength prompt)
       :unbeatable (:unbeatable prompt)
       :beat-trace (:beat-trace prompt)
       :link (:link prompt)
       :corp-credits (:corp-credits prompt)
       :runner-credits (:runner-credits prompt)}
      [:prompt-type :source-card :choices :show-discard :show-opponent-discard
       :offer-bad-pub? :player :base :bonus :strength :unbeatable :beat-trace
       :link :corp-credits :runner-credits]))))

(defn- canonical-servers
  [servers side]
  (into {}
        (map (fn [[server server-state]]
               [(kw->segment server)
                {:content (canonical-cards (:content server-state) [side :servers server :content] nil)
                 :ices (canonical-cards (:ices server-state) [side :servers server :ices] nil)}]))
        servers))

(defn- canonical-rig
  [rig]
  (into {}
        (map (fn [[slot cards]]
               [(kw->segment slot) (canonical-cards cards [:runner :rig slot] nil)]))
        rig))

(defn- canonical-player
  [player side]
  (let [path-side (keyword side)
        base {:identity (canonical-card (:identity player) [path-side :identity] nil)
              :basic-action-card (canonical-card (:basic-action-card player) [path-side :basic-action-card] nil)
              :click (:click player)
              :click-per-turn (:click-per-turn player)
              :credit (:credit player)
              :agenda-point (:agenda-point player)
              :agenda-point-req (:agenda-point-req player)
              :hand-size (:hand-size player)
              :deck-count (:deck-count player)
              :hand-count (:hand-count player)
              :bad-publicity (:bad-publicity player)
              :run-credit (:run-credit player)
              :bad-pub-credit (:bad-pub-credit player)
              :link (:link player)
              :tag (:tag player)
              :memory (:memory player)
              :brain-damage (:brain-damage player)
              :keep (:keep player)
              :prompt-state (canonical-prompt (:prompt-state player))
              :runnable-list (:runnable-list player)
              :install-list (:install-list player)
              :deck (canonical-cards (:deck player) [path-side :deck] nil)
              :hand (canonical-cards (:hand player) [path-side :hand] nil)
              :discard (canonical-cards (:discard player) [path-side :discard] nil)
              :scored (canonical-cards (:scored player) [path-side :scored] nil)
              :rfg (canonical-cards (:rfg player) [path-side :rfg] nil)
              :play-area (canonical-cards (:play-area player) [path-side :play-area] nil)
              :current (canonical-cards (:current player) [path-side :current] nil)
              :set-aside (canonical-cards (:set-aside player) [path-side :set-aside] nil)}
        corp-extra (when (= :corp path-side)
                     {:servers (canonical-servers (:servers player) :corp)})
        runner-extra (when (= :runner path-side)
                       {:rig (canonical-rig (:rig player))})]
    (merge (select-non-nil-keys
             base
             [:identity :basic-action-card :click :click-per-turn :credit :agenda-point :agenda-point-req
              :hand-size :deck-count :hand-count :bad-publicity :run-credit :bad-pub-credit
              :link :tag :memory :brain-damage :keep :prompt-state :runnable-list :install-list
              :deck :hand :discard :scored :rfg :play-area :current :set-aside])
           corp-extra
           runner-extra)))

(defn- canonical-run
  [run]
  (when run
    (select-non-nil-keys
      {:server (some->> (:server run) (mapv kw->segment))
       :position (:position run)
       :phase (:phase run)
       :next-phase (:next-phase run)
       :cannot-jack-out (:cannot-jack-out run)
       :corp-auto-no-action (:corp-auto-no-action run)
       :no-action (:no-action run)
       :approached-ice-in-position? (:approached-ice-in-position? run)
       :jack-out-available (:jack-out-available run)}
      [:server :position :phase :next-phase :cannot-jack-out :corp-auto-no-action
       :no-action :approached-ice-in-position? :jack-out-available])))

(defn- canonical-encounters
  [encounters]
  (when encounters
    (select-non-nil-keys
      {:encounter-count (:encounter-count encounters)
       :no-action (:no-action encounters)
       :ice (some-> (:ice encounters)
                    (select-non-nil-keys [:code :title :printed-title :side :rezzed :facedown :zone]))}
      [:encounter-count :no-action :ice])))

(defn- canonical-state
  [state]
  (select-non-nil-keys
    {:format (:format state)
     :seed (:seed state)
     :rng-seed (:rng-seed state)
     :active-player (:active-player state)
     :turn (:turn state)
     :corp-phase-12 (:corp-phase-12 state)
     :runner-phase-12 (:runner-phase-12 state)
     :corp-post-discard (:corp-post-discard state)
     :runner-post-discard (:runner-post-discard state)
     :end-turn (:end-turn state)
     :winner (:winner state)
     :reason (:reason state)
     :mark (:mark state)
     :run (canonical-run (:run state))
     :encounters (canonical-encounters (:encounters state))
     :corp (canonical-player (:corp state) "corp")
     :runner (canonical-player (:runner state) "runner")}
    [:format :seed :rng-seed :active-player :turn :corp-phase-12 :runner-phase-12
     :corp-post-discard :runner-post-discard :end-turn :winner :reason :mark
     :run :encounters :corp :runner]))

(defn- decision-side
  [corp-observation runner-observation]
  (let [corp-prompt-raw (get-in corp-observation [:corp :prompt-state])
        runner-prompt-raw (get-in runner-observation [:runner :prompt-state])
        corp-prompt (when-not (hide-only-prompt? corp-prompt-raw) corp-prompt-raw)
        runner-prompt (when-not (hide-only-prompt? runner-prompt-raw) runner-prompt-raw)
        run (:run corp-observation)]
    (cond
      (and run
           (= :run (:prompt-type corp-prompt))
           (= :run (:prompt-type runner-prompt)))
      (if (= :corp (:no-action run)) :runner :corp)

      (and corp-prompt (not= :waiting (:prompt-type corp-prompt))) :corp
      (and runner-prompt (not= :waiting (:prompt-type runner-prompt))) :runner
      (and (:end-turn corp-observation)
           (not (:corp-post-discard corp-observation))
           (not (:runner-post-discard corp-observation)))
      (other-side (:active-player corp-observation))
      :else (:active-player corp-observation))))

(declare card-actions)

(defn- prompt-actions
  [side prompt run]
  (let [choices (or (filter-hide-choices (:choices prompt))
                    (:choices prompt))]
    (when (and prompt
               (not= :waiting (:prompt-type prompt))
               (not (hide-only-prompt? prompt)))
      (cond
        (= :run (:prompt-type prompt))
        (let [base-action {:kind :continue
                           :side side
                           :prompt-type (:prompt-type prompt)}]
          (if (and (= side :runner) (:jack-out-available run))
            [base-action {:kind :jack-out
                          :side :runner
                          :prompt-type (:prompt-type prompt)
                          :label "Jack out"}]
            [base-action]))

        (seq choices)
        (mapv (fn [choice]
                {:kind :prompt-choice
                 :side side
                 :prompt-type (:prompt-type prompt)
                 :choice choice})
              choices)

        :else nil))))

(defn- abilities->actions
  [kind side loc abilities]
  (->> abilities
       (filter :playable)
       (mapv (fn [{:keys [index label]}]
               {:kind kind
                :side side
                :card-locator loc
                :ability-index index
                :label label}))))

(defn- card-actions
  [side zone-name card]
  (let [loc (:locator card)
        hosted-actions (mapcat #(card-actions side zone-name %) (:hosted card))
        play-actions (cond-> []
                       (and (= zone-name :hand) (:playable card))
                       (conj {:kind :play-from-hand
                              :side side
                              :card-locator loc
                              :card-title (:title card)})
                       (and (= zone-name :discard) (:flashback-playable card))
                       (conj {:kind :flashback
                              :side side
                              :card-locator loc
                              :card-title (:title card)}))
        ability-actions (concat
                          (abilities->actions :use-ability side loc (:abilities card))
                          (abilities->actions :use-corp-ability side loc (:corp-abilities card))
                          (abilities->actions :use-runner-ability side loc (:runner-abilities card))
                          (->> (:subroutines card)
                               (filter :resolve)
                               (mapv (fn [{:keys [index label]}]
                                       {:kind :use-subroutine
                                        :side side
                                        :card-locator loc
                                        :subroutine-index index
                                        :label label}))))]
    (concat play-actions ability-actions hosted-actions)))

(defn- zone-actions
  [side zone-name cards]
  (mapcat #(card-actions side zone-name %) cards))

(defn- root-actions
  [side observation]
  (let [player (get observation side)
        side-name (keyword side)
        corp-server-actions (when (= side-name :corp)
                              (mapcat (fn [[server data]]
                                        (concat (zone-actions side :server-content (:content data))
                                                (zone-actions side :server-ice (:ices data))))
                                      (:servers player)))
        runner-rig-actions (when (= side-name :runner)
                             (mapcat (fn [[_slot cards]]
                                       (zone-actions side :rig cards))
                                     (:rig player)))
        card-actions* (concat
                        (zone-actions side :identity [(:identity player)])
                        (zone-actions side :basic-action-card [(:basic-action-card player)])
                        (zone-actions side :hand (:hand player))
                        (zone-actions side :discard (:discard player))
                        (zone-actions side :scored (:scored player))
                        (zone-actions side :play-area (:play-area player))
                        (zone-actions side :current (:current player))
                        (zone-actions side :set-aside (:set-aside player))
                        corp-server-actions
                        runner-rig-actions)
        runnable-actions (when (= side-name :runner)
                           (mapv (fn [server]
                                   {:kind :run
                                    :side side
                                    :server server})
                                 (:runnable-list player)))]
    (concat card-actions* runnable-actions)))

(defn- start-turn-actions
  [side observation]
  (when (and (:end-turn observation)
             (not (:corp-post-discard observation))
             (not (:runner-post-discard observation)))
    [{:kind :start-turn
      :side side}]))

(defn- end-turn-actions
  [side observation]
  (let [player (get observation side)
        phase-locked (or (:corp-phase-12 observation)
                         (:runner-phase-12 observation)
                         (:corp-post-discard observation)
                         (:runner-post-discard observation))]
    (when (and (= side (:active-player observation))
               (zero? (:click player))
               (not (:end-turn observation))
               (not phase-locked))
      [{:kind :end-turn
        :side side}])))

(defn- action-sort-key
  [action]
  [(name (:kind action))
   (name (:side action))
   (pr-str (:card-locator action))
   (or (:ability-index action) -1)
   (or (:subroutine-index action) -1)
   (or (:server action) "")
   (pr-str (:choice action))
   (or (:label action) "")
   (or (:card-title action) "")])

(defn legal-actions
  [corp-observation runner-observation]
  (let [side (decision-side corp-observation runner-observation)
        observation (if (= side :corp) corp-observation runner-observation)
        prompt (get-in observation [side :prompt-state])
        run (:run corp-observation)
        actions (if (and prompt (not= :waiting (:prompt-type prompt)))
                  (prompt-actions side prompt run)
                  (or (start-turn-actions side observation)
                      (end-turn-actions side observation)
                      (root-actions side observation)))]
    {:decision-side side
     :actions (vec (sort-by action-sort-key actions))}))

(defn- resolve-card
  [state loc]
  (get-in @state (mapv segment->path-key loc)))

(defn- resolve-action-card
  [state side {:keys [card-locator card-index card-title]}]
  (let [card-from-locator (when card-locator (resolve-card state card-locator))]
    (or card-from-locator
        (when (some? card-title)
          (some #(when (= card-title (:title %)) %) (get-in @state [side :hand])))
        (when (some? card-index)
          (get-in @state [side :hand card-index])))))

(defn- resolve-installed-card
  [state side {:keys [card-locator card-index card-title]}]
  (let [card-from-locator (when card-locator (resolve-card state card-locator))]
    (or card-from-locator
        (when (some? card-title)
          (some #(when (= card-title (:title %)) %) (get-in @state [side :rig :resource])))
        (when (some? card-index)
          (get-in @state [side :rig :resource card-index])))))

(defn- require-card!
  [card action]
  (or card
      (throw (ex-info "Unable to resolve card for parity replay action"
                      {:action action}))))

(defn- resolve-ability-card
  [state side {:keys [card-locator]}]
  (or (some->> card-locator
               (resolve-card state))
      (get-in @state [side :basic-action-card])))

(defn- resolve-prompt-choice
  [state side {:keys [choice-type value card] :as choice}]
  (let [prompt (or (first (get-in @state [side :prompt]))
                   (get-in @state [side :prompt-state]))
        choices (:choices prompt)]
    (cond
      (and (sequential? choices)
           (seq choices)
           (map? (first choices)))
      (if-let [match (case choice-type
                       :card (first (filter #(= (select-non-nil-keys (:value %) [:code :title :printed-title :side])
                                                card)
                                            choices))
                       (first (filter #(= (:value %) value) choices)))]
        {:uuid (:uuid match)}
        value)

      :else
      value)))

(defn- apply-action!
  [state action]
  (let [side (:side action)]
    (case (:kind action)
      :prompt-choice
      (main/handle-action state side "choice" {:choice (resolve-prompt-choice state side (:choice action))})

      :play-from-hand
      (main/handle-action state side "play" {:card (require-card! (resolve-action-card state side action) action)})

      :install-from-hand
      (main/handle-action state side "play" {:card (require-card! (resolve-action-card state side action) action)})

      :flashback
      (main/handle-action state side "flashback" {:card (resolve-card state (:card-locator action))})

      :use-ability
      (main/handle-action state side "ability" {:card (resolve-ability-card state side action)
                                                :ability (:ability-index action)})

      :use-installed-ability
      (main/handle-action state side "ability" {:card (require-card! (resolve-installed-card state side action) action)
                                                :ability (:ability-index action)})

      :use-corp-ability
      (main/handle-action state side "corp-ability" {:card (resolve-ability-card state side action)
                                                     :ability (:ability-index action)})

      :use-runner-ability
      (main/handle-action state side "runner-ability" {:card (resolve-ability-card state side action)
                                                       :ability (:ability-index action)})

      :run
      (main/handle-action state side "run" {:server (:server action)})

      :continue
      (main/handle-action state side "continue" nil)

      :jack-out
      (main/handle-action state side "jack-out" nil)

      :start-turn
      (main/handle-action state side "start-turn" nil)

      :end-turn
      (main/handle-action state side "end-turn" nil)

      :use-subroutine
      (main/handle-action state side "subroutine" {:card (resolve-card state (:card-locator action))
                                                   :subroutine (:subroutine-index action)})

      :score
      (let [card (resolve-card state (:card-locator action))]
        (main/handle-action state side "score" {:card card}))

      :advance
      (let [card (resolve-card state (:card-locator action))]
        (main/handle-action state side "advance" {:card card}))

      :select
      (let [card-title (:card-title action)
            hand (get-in @state [side :hand])
            card (some #(when (= card-title (:title %)) %) hand)]
        (when card
          (main/handle-action state side "select" {:card card})))

      (throw (ex-info "Unsupported parity action" {:action action})))))

(defn- transient-hide-action?
  [action]
  (and (= :prompt-choice (:kind action))
       (= "Hide" (get-in action [:choice :value]))))

(defn- ack-top-toast!
  [state side]
  (when-let [toast-id (some-> (get-in @state [side :toast]) first :id)]
    (main/handle-action state side "toast" {:id (str toast-id)})
    true))

(defn- clear-hide-only-prompt!
  [state side]
  (let [prompt-queue (vec (get-in @state [side :prompt]))
        active-prompt (or (first prompt-queue)
                          (get-in @state [side :prompt-state]))]
    (when (hide-only-prompt? active-prompt)
      (let [remaining (if (seq prompt-queue) (vec (rest prompt-queue)) prompt-queue)
            next-prompt (first remaining)]
        (swap! state (fn [s]
                       (-> s
                           (assoc-in [side :prompt] remaining)
                           (assoc-in [side :prompt-state] next-prompt))))
        (ack-top-toast! state side)
        true))))

(defn- auto-dismiss-hide-prompts!
  [state]
  (loop [remaining 12]
    (when (pos? remaining)
      (let [cleared? (or (clear-hide-only-prompt! state :corp)
                         (clear-hide-only-prompt! state :runner))]
        (when cleared?
          (recur (dec remaining))))))
  state)

(defn- clear-leading-waiting-prompt-for-side!
  [state side]
  (let [prompt-queue (vec (get-in @state [side :prompt]))
        prompt-state (get-in @state [side :prompt-state])
        active-prompt (or (first prompt-queue) prompt-state)]
    (when (= :waiting (:prompt-type active-prompt))
      (let [remaining (vec (drop-while #(= :waiting (:prompt-type %)) prompt-queue))
            next-prompt (first remaining)]
        (swap! state (fn [s]
                       (-> s
                           (assoc-in [side :prompt] remaining)
                           (assoc-in [side :prompt-state] next-prompt))))
        true))))

(defn- normalize-choice
  [choice]
  (cond-> choice
    (string? (:choice-type choice)) (update :choice-type keyword)
    (and (:card choice) (string? (get-in choice [:card :side])))
    (update-in [:card :side] (fn [s] (keyword (string/lower-case s))))))

(defn normalize-action
  [action]
  (cond-> action
    (string? (:kind action)) (update :kind keyword)
    (string? (:side action)) (update :side keyword)
    (string? (:prompt-type action)) (update :prompt-type keyword)
    (:choice action) (update :choice normalize-choice)))

(defn canonical-bundle
  [state]
  (let [{corp-state :corp-state
         runner-state :runner-state} (diffs/public-states state)
        corp-observation (canonical-state corp-state)
        runner-observation (canonical-state runner-state)
        {:keys [decision-side actions]} (legal-actions corp-observation runner-observation)]
    {:oracle-state (canonical-state @state)
     :observations {:corp corp-observation
                    :runner runner-observation}
     :decision-side decision-side
     :legal-actions actions}))

(defn bundle-after-actions
  ([actions]
   (bundle-after-actions 1 actions))
  ([seed actions]
   (let [state (beginner-state seed)]
     (doseq [action actions]
       (apply-action! state (normalize-action action)))
     (canonical-bundle state))))

(defn replay-bundle-after-actions
  ([actions]
   (replay-bundle-after-actions 1 actions))
  ([seed actions]
   (replay-bundle-after-actions seed actions nil))
  ([seed actions matchup]
   (let [state (if (= matchup "system-gateway-intermediate")
                 (intermediate-state seed)
                 (beginner-state seed))]
     (swap! state assoc :run-ice-windows-enabled true)
     (doseq [action actions]
       (let [normalized-action (normalize-action action)]
         (auto-dismiss-hide-prompts! state)
         (clear-leading-waiting-prompt-for-side! state (:side normalized-action))
         (apply-action! state normalized-action)))
     (auto-dismiss-hide-prompts! state)
     (canonical-bundle state))))

(defn- export-transition-tree
  [make-state actions depth]
  (mapv (fn [action]
        (let [state (make-state)
              _ (apply-action! state action)
              result (canonical-bundle state)
                node {:action action
                      :result result}]
            (if (pos? depth)
              (assoc node :transitions
                     (export-transition-tree
                       (fn []
                         (let [child-state (make-state)]
                           (apply-action! child-state action)
                           child-state))
                       (:legal-actions result)
                       (dec depth)))
              node)))
        actions))

(defn beginner-init-fixture
  ([]
   (beginner-init-fixture 1))
  ([seed]
   (let [initial-state (beginner-state seed)
         initial (canonical-bundle initial-state)
         transitions (export-transition-tree #(beginner-state seed) (:legal-actions initial) 4)]
     {:fixture-version 1
      :fixture-kind :initial-state
      :matchup :system-gateway-beginner
      :seed seed
      :initial initial
      :transitions transitions})))

(defn export-beginner-init-fixture!
  ([]
   (export-beginner-init-fixture! default-export-path 1))
  ([path]
   (export-beginner-init-fixture! path 1))
  ([path seed]
   (let [fixture (beginner-init-fixture seed)
         file (io/file path)]
     (io/make-parents file)
     (spit file (json/generate-string fixture {:pretty true}))
     fixture)))

(defn -main
  [& [path seed]]
  (let [seed (if seed (Long/parseLong seed) 1)
        path (or path default-export-path)]
    (export-beginner-init-fixture! path seed)
    (println "Wrote parity fixture to" path)))
