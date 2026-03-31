#ifndef NETRUNNER_H
#define NETRUNNER_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque game handle */
typedef void* NetrunnerGame;

/* Matchup IDs */
#define NETRUNNER_MATCHUP_SG_BEGINNER     0
#define NETRUNNER_MATCHUP_SG_INTERMEDIATE 1
#define NETRUNNER_MATCHUP_SG_FULLPACK     2

/* Player IDs */
#define NETRUNNER_CORP   0
#define NETRUNNER_RUNNER 1

/* ---- Game lifecycle ---- */
NetrunnerGame netrunner_create(int matchup_id, uint64_t seed);
void          netrunner_destroy(NetrunnerGame game);

/* ---- Core game state ---- */
int  netrunner_current_player(NetrunnerGame game);   /* 0=corp, 1=runner, -1=error */
bool netrunner_is_terminal(NetrunnerGame game);
int  netrunner_winner(NetrunnerGame game);            /* 0=corp, 1=runner, -1=none */
int  netrunner_turn(NetrunnerGame game);
int  netrunner_active_player(NetrunnerGame game);

/* ---- Actions ---- */
int netrunner_num_actions(NetrunnerGame game);
int netrunner_apply_action(NetrunnerGame game, int action_index);  /* 0=ok */
int netrunner_action_description(NetrunnerGame game, int index, char* buf, int buf_size);

/* ---- Player state ---- */
int netrunner_player_credits(NetrunnerGame game, int player);
int netrunner_player_clicks(NetrunnerGame game, int player);
int netrunner_player_hand_size(NetrunnerGame game, int player);
int netrunner_player_deck_size(NetrunnerGame game, int player);
int netrunner_player_discard_size(NetrunnerGame game, int player);
int netrunner_player_score(NetrunnerGame game, int player);
int netrunner_player_score_req(NetrunnerGame game, int player);
int netrunner_identity_name(NetrunnerGame game, int player, char* buf, int buf_size);

/* ---- Runner-specific ---- */
int netrunner_runner_mu_used(NetrunnerGame game);
int netrunner_runner_mu_available(NetrunnerGame game);
int netrunner_runner_link(NetrunnerGame game);
int netrunner_runner_tags(NetrunnerGame game);
int netrunner_runner_run_credits(NetrunnerGame game);

/* ---- Corp-specific ---- */
int netrunner_corp_bad_pub(NetrunnerGame game);

/* ---- Board inspection: servers ---- */
int  netrunner_server_count(NetrunnerGame game);
int  netrunner_server_name(NetrunnerGame game, int idx, char* buf, int buf_size);
int  netrunner_server_ice_count(NetrunnerGame game, int server_idx);
int  netrunner_server_ice_name(NetrunnerGame game, int server_idx, int ice_idx, char* buf, int buf_size);
bool netrunner_server_ice_rezzed(NetrunnerGame game, int server_idx, int ice_idx);
int  netrunner_server_content_count(NetrunnerGame game, int server_idx);
int  netrunner_server_content_name(NetrunnerGame game, int server_idx, int card_idx, char* buf, int buf_size);
bool netrunner_server_content_rezzed(NetrunnerGame game, int server_idx, int card_idx);

/* ---- Board inspection: runner rig ---- */
int netrunner_rig_program_count(NetrunnerGame game);
int netrunner_rig_hardware_count(NetrunnerGame game);
int netrunner_rig_resource_count(NetrunnerGame game);
int netrunner_rig_program_name(NetrunnerGame game, int idx, char* buf, int buf_size);
int netrunner_rig_hardware_name(NetrunnerGame game, int idx, char* buf, int buf_size);
int netrunner_rig_resource_name(NetrunnerGame game, int idx, char* buf, int buf_size);

/* ---- Hand contents (local play) ---- */
int netrunner_hand_card_name(NetrunnerGame game, int player, int idx, char* buf, int buf_size);

/* ---- Run state ---- */
bool netrunner_is_run_active(NetrunnerGame game);
int  netrunner_run_server(NetrunnerGame game, char* buf, int buf_size);
int  netrunner_run_phase(NetrunnerGame game, char* buf, int buf_size);
int  netrunner_run_position(NetrunnerGame game);

/* ---- Prompt state ---- */
int netrunner_prompt_type(NetrunnerGame game, int player, char* buf, int buf_size);
int netrunner_prompt_source(NetrunnerGame game, int player, char* buf, int buf_size);

#ifdef __cplusplus
}
#endif

#endif /* NETRUNNER_H */
