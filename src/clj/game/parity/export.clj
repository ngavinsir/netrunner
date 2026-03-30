(ns game.parity.export
  (:require
   [cheshire.core :as json]
   [clojure.edn :as edn]
   [clojure.java.io :as io]
   [clojure.string :as string]
   [game.core.card :as card]
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

(defn- register-advanced-cards!
  []
  (let [corp (prepare-precon-deck "Corp" preconstructed/gateway-advanced-corp)
        runner (prepare-precon-deck "Runner" preconstructed/gateway-advanced-runner)
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

(defn advanced-game
  ([]
   (advanced-game 1))
  ([seed]
   (let [corp preconstructed/gateway-advanced-corp
         runner preconstructed/gateway-advanced-runner]
     {:gameid 1
      :format "system-gateway"
      :seed seed
      :players [{:side "Corp"
                 :user {:username "Corp"}
                 :deck (prepare-precon-deck "Corp" corp)}
                {:side "Runner"
                 :user {:username "Runner"}
                 :deck (prepare-precon-deck "Runner" runner)}]})))

(defn advanced-state
  ([]
   (advanced-state 1))
  ([seed]
   (ensure-card-defs-loaded!)
   (register-advanced-cards!)
   (set-up/init-game (advanced-game seed))))

(defn- register-complete-cards!
  []
  (let [corp (prepare-precon-deck "Corp" preconstructed/gateway-complete-corp)
        runner (prepare-precon-deck "Runner" preconstructed/gateway-complete-runner)
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

(defn complete-game
  ([]
   (complete-game 1))
  ([seed]
   (let [corp preconstructed/gateway-complete-corp
         runner preconstructed/gateway-complete-runner]
     {:gameid 1
      :format "system-gateway"
      :seed seed
      :players [{:side "Corp"
                 :user {:username "Corp"}
                 :deck (prepare-precon-deck "Corp" corp)}
                {:side "Runner"
                 :user {:username "Runner"}
                 :deck (prepare-precon-deck "Runner" runner)}]})))

(defn complete-state
  ([]
   (complete-state 1))
  ([seed]
   (ensure-card-defs-loaded!)
   (register-complete-cards!)
   (set-up/init-game (complete-game seed))))

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
       (let [choices (:choices prompt)]
         (and (seq choices)
              (every? (fn [choice]
                        (or (= "Hide" choice)
                            (= "Hide" (:value choice))))
                      choices)))))

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
  (when prompt
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

      ;; During a run, if corp has only a :run prompt and runner has a
      ;; non-run/non-waiting prompt (e.g. access), runner gets priority.
      (and run
           (= :run (:prompt-type corp-prompt))
           runner-prompt
           (not= :run (:prompt-type runner-prompt))
           (not= :waiting (:prompt-type runner-prompt)))
      :runner

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
          (or (some #(when (= card-title (:title %)) %) (get-in @state [side :rig :resource]))
              (some #(when (= card-title (:title %)) %) (get-in @state [side :rig :program]))
              (some #(when (= card-title (:title %)) %) (get-in @state [side :rig :hardware])))))))

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
                       :card (or
                               ;; Standard wrapped choices: {:value card-data, :uuid uuid}
                               (first (filter #(= (select-non-nil-keys (:value %) [:code :title :printed-title :side])
                                                  card)
                                              choices))
                               ;; Raw card choices (e.g. runner-host-choice passes card objects directly)
                               (first (filter #(= (select-non-nil-keys % [:code :title :printed-title :side])
                                                  card)
                                              choices)))
                       (first (filter #(= (:value %) value) choices)))]
        (if (:uuid match) {:uuid (:uuid match)} match)
        value)

      :else
      value)))

(defn- auto-resolve-break-prompts!
  "After activating an icebreaker break or bioroid break ability in the oracle,
  auto-select all subroutines from the resulting prompts until the encounter resumes.
  Clojure's auto-repeat handles re-activating the ability for additional sub batches."
  [state side]
  (loop [remaining 30]
    (when (pos? remaining)
      (let [prompt (first (filter #(not= :waiting (:prompt-type %))
                                  (get-in @state [side :prompt])))]
        (when (and prompt (seq (:choices prompt)))
          (let [choices (:choices prompt)
                choice-val (fn [c] (if (map? c) (:value c) (str c)))
                sub-choice (first (remove #(= "Done" (choice-val %)) choices))
                done-choice (first (filter #(= "Done" (choice-val %)) choices))]
            (cond
              ;; Select a sub choice (auto-select all breakable subs)
              sub-choice
              (do (main/handle-action state side "choice" {:choice sub-choice})
                  (recur (dec remaining)))
              ;; Only "Done" left — click it to complete the break activation
              done-choice
              (do (main/handle-action state side "choice" {:choice done-choice})
                  (recur (dec remaining)))
              ;; No actionable choices
              :else nil)))))))

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
      (let [card (require-card! (resolve-installed-card state side action) action)
            ability-idx (:ability-index action)]
        (main/handle-action state side "ability" {:card card :ability ability-idx})
        ;; After activating an icebreaker break ability (index 0) during encounter,
        ;; auto-resolve the sub selection prompts that Clojure creates.
        (when (and (= 0 ability-idx) (get-in @state [:run :current-ice]))
          (auto-resolve-break-prompts! state side)))

      :use-corp-ability
      (main/handle-action state side "corp-ability" {:card (resolve-ability-card state side action)
                                                     :ability (:ability-index action)})

      :use-runner-ability
      (let [card-title (:card-title action)
            ;; For bioroid breaks, find the current ICE card
            current-ice (get-in @state [:run :current-ice])
            ice-card (when current-ice (card/get-card state current-ice))
            ;; Use card-title to distinguish: if it matches the ICE, it's a bioroid break
            card (if (and ice-card (= card-title (:title ice-card)))
                   ice-card
                   (resolve-ability-card state side action))]
        (main/handle-action state side "runner-ability" {:card card
                                                         :ability (:ability-index action)})
        ;; Auto-resolve bioroid break sub selection prompts
        (when (and ice-card (= card-title (:title ice-card)))
          (auto-resolve-break-prompts! state side)))

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
      (let [current-ice (get-in @state [:run :current-ice])
            ice-card (when current-ice (card/get-card state current-ice))]
        (main/handle-action state side "subroutine" {:card (or ice-card current-ice)
                                                     :subroutine (:subroutine-index action)}))

      :funhouse-encounter
      ;; Funhouse on-encounter: resolve via handle-action "choice".
      ;; After the choice resolves, Clojure's async chain continues the encounter
      ;; (firing subs automatically). Auto-resolve any resulting prompts.
      (let [choice (:choice action)
            prompt (first (filter #(not= :waiting (:prompt-type %))
                                  (get-in @state [:runner :prompt])))
            choices (:choices prompt)
            match (first (filter #(= choice (if (map? %) (:value %) (str %))) choices))]
        (when match
          (main/handle-action state :runner "choice" {:choice match})))

      :retribution-trash
      ;; Retribution trashes a runner hardware or program via card-selection (select) prompt.
      ;; Resolve by finding the card from the locator path in the runner's rig.
      (let [card (when-let [loc (:card-locator action)]
                   (resolve-card state loc))
            prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt])))
            prompt-eid (:eid prompt)]
        (when card
          (main/handle-action state :corp "select" {:card card :eid prompt-eid})
          ;; Auto-click "Done" if the select prompt is still active
          (when-let [p (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt])))]
            (when-let [done-choice (first (filter #(= "Done" (:value %)) (:choices p)))]
              (main/handle-action state :corp "choice" {:choice {:uuid (:uuid done-choice)}})))))

      :manegarm-tax
      ;; Resolve Manegarm's approach-server prompt properly through the prompt system.
      (let [choice (:choice action)
            runner-prompts (get-in @state [:runner :prompt])
            prompt (first (filter #(not= :waiting (:prompt-type %)) runner-prompts))
            choices (:choices prompt)
            match (first (filter #(= choice (if (map? %) (:value %) (str %))) choices))]
        (when match
          (main/handle-action state :runner "choice" {:choice match})))

      :rez
      (let [card (when-let [loc (:card-locator action)]
                   (resolve-card state loc))]
        (when card
          (main/handle-action state side "rez" {:card card})))

      :rez-ice
      ;; Rez the approached ICE. Use run position to find the ICE.
      (let [run (:run @state)
            run-ices (get-in @state (concat [:corp :servers] (:server run) [:ices]))
            pos (:position run)
            ice-card (when (and run-ices pos (pos? pos) (<= pos (count run-ices)))
                       (nth run-ices (dec pos)))]
        (when ice-card
          (main/handle-action state side "rez" {:card ice-card})))

      :score
      (let [card (resolve-card state (:card-locator action))]
        (main/handle-action state side "score" {:card card}))

      :advance
      (let [card (resolve-card state (:card-locator action))]
        (main/handle-action state side "advance" {:card card}))

      :select
      (let [card (or (when-let [loc (:card-locator action)]
                       (resolve-card state loc))
                     (let [card-title (:card-title action)]
                       (or (some #(when (= card-title (:title %)) %) (get-in @state [side :hand]))
                           (some #(when (= card-title (:title %)) %) (get-in @state [side :rig :program]))
                           (some #(when (= card-title (:title %)) %) (get-in @state [side :rig :resource]))
                           (some #(when (= card-title (:title %)) %) (get-in @state [side :rig :hardware])))))
            ;; Pass the select prompt's eid so the engine can match the card to the correct selection entry
            prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [side :prompt])))
            prompt-eid (:eid prompt)]
        (when card
          (main/handle-action state side "select" {:card card :eid prompt-eid})
          ;; Auto-click "Done" if there's still a select prompt (e.g., MU overflow multi-select).
          ;; Zig sends one select per card; Clojure's multi-select needs explicit Done.
          ;; If the select auto-resolved (max reached), the prompt is already gone.
          (when-let [prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [side :prompt])))]
            (when-let [done-choice (first (filter #(= "Done" (:value %)) (:choices prompt)))]
              (main/handle-action state side "choice" {:choice {:uuid (:uuid done-choice)}})))))

      :sprint-shuffle
      ;; Sprint: corp chooses a card from HQ to shuffle into R&D.
      ;; The select prompt may be wrapped in a "Hide" select — get eid from :selected.
      (let [card-title (:choice action)
            hand (get-in @state [:corp :hand])
            card (first (filter #(= card-title (:title %)) hand))
            selected (first (get-in @state [:corp :selected]))
            select-eid (or (:eid (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt]))))
                          (:eid selected))]
        (when (and card select-eid)
          (main/handle-action state :corp "select" {:card card :eid select-eid})))

      :hansei-trash
      ;; Hansei Review: corp chooses a card from HQ to trash.
      ;; The select prompt may be wrapped in a "Hide" select — get eid from :selected.
      (let [card-title (:choice action)
            hand (get-in @state [:corp :hand])
            card (first (filter #(= card-title (:title %)) hand))
            selected (first (get-in @state [:corp :selected]))
            select-eid (or (:eid (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt]))))
                          (:eid selected))]
        (when (and card select-eid)
          (main/handle-action state :corp "select" {:card card :eid select-eid})))

      :ballista-trash
      ;; Ballista subroutine: corp chooses a runner program to trash.
      (let [card (when-let [loc (:card-locator action)]
                   (resolve-card state loc))
            prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt])))
            prompt-eid (:eid prompt)]
        (when card
          (main/handle-action state :corp "select" {:card card :eid prompt-eid})
          (when-let [p (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt])))]
            (when-let [done-choice (first (filter #(= "Done" (:value %)) (:choices p)))]
              (main/handle-action state :corp "choice" {:choice {:uuid (:uuid done-choice)}})))))

      :above-the-law-trash
      ;; Above the Law: corp chooses a runner resource to trash on score.
      (let [card (when-let [loc (:card-locator action)]
                   (resolve-card state loc))
            prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt])))
            prompt-eid (:eid prompt)]
        (when card
          (main/handle-action state :corp "select" {:card card :eid prompt-eid})
          (when-let [p (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt])))]
            (when-let [done-choice (first (filter #(= "Done" (:value %)) (:choices p)))]
              (main/handle-action state :corp "choice" {:choice {:uuid (:uuid done-choice)}})))))

      :anoetic-void
      ;; Anoetic Void: corp chooses to use ability (pay 2cr + trash 2 from HQ -> ETR).
      ;; In Clojure, this fires as a paid ability prompt on the corp side.
      (let [choice (:choice action)
            corp-prompts (get-in @state [:corp :prompt])
            prompt (first (filter #(not= :waiting (:prompt-type %)) corp-prompts))
            choices (:choices prompt)
            match (first (filter #(= choice (if (map? %) (:value %) (str %))) choices))]
        (when match
          (main/handle-action state :corp "choice" {:choice match})))

      :trojan-host
      ;; Trojan host selection — Clojure uses :select prompt where user clicks an ICE card.
      ;; Find the ICE by title across all servers and send as "select" action.
      (let [card-ref (:card (:choice action))
            ice-title (or (:title card-ref) (:printed-title card-ref))
            ice-card (when ice-title
                       (some (fn [[_ server-data]]
                               (some #(when (= ice-title (:title %)) %)
                                     (get server-data :ices)))
                             (get-in @state [:corp :servers])))
            prompt (first (filter #(= :select (:prompt-type %))
                                  (get-in @state [:runner :prompt])))
            select-eid (or (:eid prompt)
                          (:eid (first (get-in @state [:runner :selected]))))]
        (when (and ice-card select-eid)
          (main/handle-action state :runner "select" {:card ice-card :eid select-eid})))

      :ansel-install
      ;; Ansel 1.0 sub 2: corp chooses a card from HQ or Archives to install.
      ;; Clojure creates a select prompt for installable cards.
      (let [choice-text (:choice action)]
        ;; Parse "HQ|idx|title" or "Archives|idx|title"
        (let [parts (clojure.string/split choice-text #"\|" 3)
              zone (first parts)
              card-title (nth parts 2 nil)
              zone-key (if (= zone "HQ") :hand :discard)
              cards (get-in @state [:corp zone-key])
              card (when card-title (first (filter #(= card-title (:title %)) cards)))
              prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt])))
              select-eid (or (:eid prompt) (:eid (first (get-in @state [:corp :selected]))))]
          (when (and card select-eid)
            (main/handle-action state :corp "select" {:card card :eid select-eid})
            ;; Auto-select install location if prompted
            (when-let [install-prompt (first (filter #(not= :waiting (:prompt-type %)) (get-in @state [:corp :prompt])))]
              (when-let [first-choice (first (:choices install-prompt))]
                (main/handle-action state :corp "choice" {:choice first-choice}))))))

      :tao-swap-ice
      ;; Tao Salonga: runner picks 2 ICE to swap positions.
      ;; Clojure creates optional "Swap 2 pieces of ice?" → Yes/No, then multi-select (max 2).
      ;; Zig sends two separate tao-swap-ice actions (one per ICE).
      (let [loc (:card-locator action)
            choice (:choice action)]
        (if (= choice "Done")
          ;; Declined — click "No" on the optional prompt
          (let [prompt (first (filter #(not= :waiting (:prompt-type %)) (get-in @state [:runner :prompt])))
                choices (:choices prompt)
                no-choice (first (filter #(= "No" (if (map? %) (:value %) (str %))) choices))]
            (when no-choice
              (main/handle-action state :runner "choice" {:choice no-choice})))
          ;; ICE selection — auto-click "Yes" first if optional prompt, then select
          (do
            (let [prompt (first (filter #(not= :waiting (:prompt-type %)) (get-in @state [:runner :prompt])))
                  choices (:choices prompt)
                  yes-choice (first (filter #(= "Yes" (if (map? %) (:value %) (str %))) choices))]
              (when yes-choice
                (main/handle-action state :runner "choice" {:choice yes-choice})))
            ;; Now find and select the ICE
            (let [ice-title (:title loc)
                  card (when ice-title
                         (some (fn [[_ server-data]]
                                 (some #(when (= ice-title (:title %)) %)
                                       (get server-data :ices)))
                               (get-in @state [:corp :servers])))
                  prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [:runner :prompt])))
                  select-eid (or (:eid prompt)
                                (:eid (first (get-in @state [:runner :selected]))))]
              (when (and card select-eid)
                (main/handle-action state :runner "select" {:card card :eid select-eid}))))))

      :malapert-search
      ;; Malapert Data Vault: corp picks a non-agenda card from R&D after scoring.
      ;; Trigger ordering is auto-resolved in the post-action loop above.
      ;; At this point, the optional "Search R&D?" prompt should be active.
      (let [choice-text (:choice action)]
        ;; Handle optional "Search R&D?" Yes/No prompt
        (let [prompt (first (filter #(not= :waiting (:prompt-type %)) (get-in @state [:corp :prompt])))
              choices (:choices prompt)
              yes-choice (first (filter #(= "Yes" (if (map? %) (:value %) (str %))) choices))]
          (when yes-choice
            (main/handle-action state :corp "choice" {:choice yes-choice})))
        ;; Select the card from R&D or Done
        (if (= choice-text "Done")
          (let [prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt])))
                done-choice (first (filter #(= "Done" (:value %)) (:choices prompt)))]
            (when done-choice
              (main/handle-action state :corp "choice" {:choice {:uuid (:uuid done-choice)}})))
          (let [deck (get-in @state [:corp :deck])
                card (first (filter #(= choice-text (:title %)) deck))
                selected (first (get-in @state [:corp :selected]))
                select-eid (or (:eid (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt]))))
                               (:eid selected))]
            (when (and card select-eid)
              (main/handle-action state :corp "select" {:card card :eid select-eid})))))

      :precision-design-archive
      ;; HB: Precision Design — corp picks a card from Archives to add to HQ
      (let [choice-text (:choice action)]
        (if (= choice-text "Done")
          (let [prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt])))
                done-choice (first (filter #(= "Done" (:value %)) (:choices prompt)))]
            (when done-choice
              (main/handle-action state :corp "choice" {:choice {:uuid (:uuid done-choice)}})))
          (let [discard (get-in @state [:corp :discard])
                card (first (filter #(= choice-text (:title %)) discard))
                selected (first (get-in @state [:corp :selected]))
                select-eid (or (:eid (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt]))))
                               (:eid selected))]
            (when (and card select-eid)
              (main/handle-action state :corp "select" {:card card :eid select-eid})))))

      :reality-plus
      ;; NBN: Reality Plus — corp chooses gain 2cr or draw 2 on first tag
      (let [choice (:choice action)
            corp-prompts (get-in @state [:corp :prompt])
            prompt (first (filter #(not= :waiting (:prompt-type %)) corp-prompts))
            choices (:choices prompt)
            match (first (filter #(= choice (if (map? %) (:value %) (str %))) choices))]
        (when match
          (main/handle-action state :corp "choice" {:choice match})))

      :longevity-serum-trash
      ;; Longevity Serum: corp picks a card from HQ to trash (or "Done" to stop).
      (let [choice-text (:choice action)]
        (if (= choice-text "Done")
          ;; Click "Done" on the select prompt
          (let [prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt])))
                done-choice (first (filter #(= "Done" (:value %)) (:choices prompt)))]
            (when done-choice
              (main/handle-action state :corp "choice" {:choice {:uuid (:uuid done-choice)}})))
          ;; Select the card from HQ
          (let [hand (get-in @state [:corp :hand])
                card (first (filter #(= choice-text (:title %)) hand))
                selected (first (get-in @state [:corp :selected]))
                select-eid (or (:eid (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt]))))
                               (:eid selected))]
            (when (and card select-eid)
              (main/handle-action state :corp "select" {:card card :eid select-eid})))))

      :longevity-serum-shuffle
      ;; Longevity Serum: corp picks a card from Archives to shuffle into R&D (or "Done" to stop).
      (let [choice-text (:choice action)]
        (if (= choice-text "Done")
          (let [prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt])))
                done-choice (first (filter #(= "Done" (:value %)) (:choices prompt)))]
            (when done-choice
              (main/handle-action state :corp "choice" {:choice {:uuid (:uuid done-choice)}})))
          (let [discard (get-in @state [:corp :discard])
                card (first (filter #(= choice-text (:title %)) discard))
                selected (first (get-in @state [:corp :selected]))
                select-eid (or (:eid (first (filter #(= :select (:prompt-type %)) (get-in @state [:corp :prompt]))))
                               (:eid selected))]
            (when (and card select-eid)
              (main/handle-action state :corp "select" {:card card :eid select-eid})))))

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
    ;; Don't clear "Hide" select prompts when there are pending card selections
    ;; (e.g., Hansei Review, Sprint). The "Hide" prompt is the UI wrapper for the
    ;; card selection and removing it breaks the eid linkage needed by the select action.
    (when (and (hide-only-prompt? active-prompt)
              (empty? (get-in @state [side :selected])))
      (let [remaining (if (seq prompt-queue) (vec (rest prompt-queue)) prompt-queue)
            next-prompt (first remaining)]
        (swap! state (fn [s]
                       (-> s
                           (assoc-in [side :prompt] remaining)
                           (assoc-in [side :prompt-state] next-prompt))))
        (ack-top-toast! state side)
        true))))

(defn- auto-resolve-end-turn-discard!
  "Auto-resolve discard-to-hand-size select prompts after end-turn.
  These prompts have :all true (must select exactly :max cards).
  We pick cards from the hand to discard, selecting them one at a time
  until the auto-resolve triggers."
  [state side]
  (loop [attempts 0]
    (when (< attempts 10)
      (let [prompt (first (filter #(= :select (:prompt-type %)) (get-in @state [side :prompt])))]
        (when prompt
          (let [prompt-eid (:eid prompt)
                hand (get-in @state [side :hand])]
            (when (seq hand)
              ;; Select the first card in hand that hasn't been selected yet
              (let [card (first (filter #(not (:selected %)) hand))]
                (when card
                  (main/handle-action state side "select" {:card card :eid prompt-eid})
                  ;; Recurse to handle multi-card discards or check if resolved
                  (recur (inc attempts))))))))))
  ;; Clear any remaining waiting prompts left by the discard flow
  (doseq [s [:corp :runner]]
    (let [prompts (get-in @state [s :prompt])
          remaining (vec (remove #(= :waiting (:prompt-type %)) prompts))]
      (when (not= (count prompts) (count remaining))
        (swap! state assoc-in [s :prompt] remaining)
        (swap! state assoc-in [s :prompt-state] (first remaining))))))



(defn- auto-resolve-optional-virus-prompts!
  "Auto-resolve optional virus placement prompts (Conduit, Leech successful-run events).
  Zig places virus counters automatically; Clojure creates optional Yes/No prompts.
  Auto-click 'Yes' on these to keep the engines in sync."
  [state]
  (doseq [side [:corp :runner]]
    (loop [remaining 5]
      (when (pos? remaining)
        (let [prompt (first (filter #(not= :waiting (:prompt-type %))
                                    (get-in @state [side :prompt])))]
          (when (and prompt
                     (let [msg (or (:msg prompt) (:prompt prompt) "")]
                       (re-find #"Place \d+ virus counter" msg)))
            (let [choices (:choices prompt)
                  yes-choice (first (filter #(= "Yes" (if (map? %) (:value %) (str %))) choices))]
              (when yes-choice
                (main/handle-action state side "choice" {:choice yes-choice})
                (recur (dec remaining))))))))))

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
   (let [make-identity-state (fn [corp-id-code corp-id-title runner-id-code runner-id-title]
                               (ensure-card-defs-loaded!)
                               (register-complete-cards!)
                               (let [corp-deck (assoc preconstructed/gateway-complete-corp :identity {:title corp-id-title :side "Corp" :code corp-id-code})
                                     runner-deck (assoc preconstructed/gateway-complete-runner :identity {:title runner-id-title :side "Runner" :code runner-id-code})]
                                 (set-up/init-game {:gameid 1 :format "system-gateway" :seed seed
                                                    :players [{:side "Corp" :user {:username "Corp"} :deck (prepare-precon-deck "Corp" corp-deck)}
                                                              {:side "Runner" :user {:username "Runner"} :deck (prepare-precon-deck "Runner" runner-deck)}]})))
         state (cond
                 (= matchup "system-gateway-intermediate") (intermediate-state seed)
                 (= matchup "system-gateway-advanced") (advanced-state seed)
                 (= matchup "system-gateway-complete") (complete-state seed)
                 (= matchup "system-gateway-hb") (make-identity-state 30035 "Haas-Bioroid: Precision Design" 30076 "The Catalyst: Convention Breaker")
                 (= matchup "system-gateway-jinteki") (make-identity-state 30043 "Jinteki: Restoring Humanity" 30076 "The Catalyst: Convention Breaker")
                 (= matchup "system-gateway-nbn") (make-identity-state 30051 "NBN: Reality Plus" 30076 "The Catalyst: Convention Breaker")
                 (= matchup "system-gateway-weyland") (make-identity-state 30059 "Weyland Consortium: Built to Last" 30076 "The Catalyst: Convention Breaker")
                 (= matchup "system-gateway-zahya") (make-identity-state 30077 "The Syndicate: Profit over Principle" 30010 "Zahya Sadeghi: Versatile Smuggler")
                 (= matchup "system-gateway-loup") (make-identity-state 30077 "The Syndicate: Profit over Principle" 30001 "René \"Loup\" Arcemont: Party Animal")
                 (= matchup "system-gateway-tao") (make-identity-state 30077 "The Syndicate: Profit over Principle" 30019 "Tāo Salonga: Telepresence Magician")
                 (= matchup "system-gateway-fullpack")
                 (let [_ (ensure-card-defs-loaded!)
                       _ (register-complete-cards!)
                       corp-deck (assoc preconstructed/gateway-complete-corp
                                        :identity {:title "The Syndicate: Profit over Principle" :side "Corp" :code 30077}
                                        :cards (conj (vec (:cards preconstructed/gateway-complete-corp))
                                                     {:qty 1 :card "Ansel 1.0"}))
                       runner-deck (assoc preconstructed/gateway-complete-runner
                                          :identity {:title "Tāo Salonga: Telepresence Magician" :side "Runner" :code 30019}
                                          :cards (-> (vec (:cards preconstructed/gateway-complete-runner))
                                                     (conj {:qty 1 :card "Carnivore"})
                                                     ;; Remove 1 Fermenter to keep deck size balanced
                                                     (#(mapv (fn [c] (if (= "Fermenter" (:card c)) (assoc c :qty 1) c)) %))))]
                   (set-up/init-game {:gameid 1 :format "system-gateway" :seed seed
                                      :players [{:side "Corp" :user {:username "Corp"} :deck (prepare-precon-deck "Corp" corp-deck)}
                                                 {:side "Runner" :user {:username "Runner"} :deck (prepare-precon-deck "Runner" runner-deck)}]}))
                 :else (beginner-state seed))]
     (swap! state assoc :run-ice-windows-enabled true)
     (doseq [[idx action] (map-indexed vector actions)]
       (let [normalized-action (normalize-action action)]
         (auto-dismiss-hide-prompts! state)
         (auto-resolve-optional-virus-prompts! state)
         (clear-leading-waiting-prompt-for-side! state (:side normalized-action))
         ;; Clear stale prompt-states when no run is active
         (when-not (:run @state)
           (doseq [side [:corp :runner]]
             (when-let [ps (get-in @state [side :prompt-state])]
               (when (#{:run :waiting} (:prompt-type ps))
                 (swap! state assoc-in [side :prompt-state] nil)))
             ;; Also clear stale prompt queue entries
             (let [prompts (get-in @state [side :prompt])]
               (when (seq prompts)
                 (let [cleaned (vec (remove #(#{:run :waiting} (:prompt-type %)) prompts))]
                   (when (not= (count cleaned) (count prompts))
                     (swap! state assoc-in [side :prompt] cleaned)
                     (swap! state assoc-in [side :prompt-state] (first cleaned))))))))
         (apply-action! state normalized-action)
         ;; Complete corp phase 12 — Clojure's start-turn uses async wait-for which
         ;; doesn't finish inline. Manually call end-phase-12 to complete the mandatory
         ;; draw before the oracle captures the snapshot.
         (when (and (= :start-turn (:kind normalized-action))
                    (= :corp (:side normalized-action))
                    (:corp-phase-12 @state))
           (game.core.turns/end-phase-12 state :corp nil))
         ;; Auto-resolve optional identity prompts (Zahya "Gain credits?", etc.)
         ;; Also auto-resolve trigger ordering and optional search prompts (Malapert, etc.)
         (doseq [side [:corp :runner]]
           (when-let [prompt (first (filter #(and (= :waiting (:prompt-type %)) (not= side (:side %)))
                                            (get-in @state [side :prompt])))]
             ;; Skip waiting prompts
             nil)
           (when-let [prompt (first (filter #(not= :waiting (:prompt-type %))
                                            (get-in @state [side :prompt])))]
             (when-let [yes-choice (first (filter #(= "Yes" (if (map? %) (:value %) (str %)))
                                                  (:choices prompt)))]
               (when (re-find #"Gain \d+ \[Credits\]" (or (:msg prompt) (:prompt prompt) ""))
                 (main/handle-action state side "choice" {:choice yes-choice})))))
         ;; After end-turn, auto-resolve discard-to-hand-size select prompts.
         ;; Clojure's end-turn async chain handles discards internally; the waiting
         ;; prompt eid mismatch prevents proper cleanup via effect-completed.
         (when (= :end-turn (:kind normalized-action))
           (auto-resolve-end-turn-discard! state (:side normalized-action)))))
     (auto-dismiss-hide-prompts! state)
     (auto-resolve-optional-virus-prompts! state)
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
