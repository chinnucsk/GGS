%% @doc This module represents a table with players

-module(ggs_table).
-behaviour(gen_server).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, { players, game_vm, already_defined } ).

%% API
-export([start/1,
	add_player/2,
	already_defined/1,
	remove_player/2,
	stop/1,
	notify/3,
	notify_all_players/2,
	notify_game/3,
	get_player_list/1,
	send_command/3]).


%% ----------------------------------------------------------------------
% API implementation

% @doc returns a new table
start(Token) ->
    {ok, Pid} = gen_server:start(?MODULE, [Token], []),
	Pid.

%% @private
call(Pid, Msg) ->
    gen_server:call(Pid, Msg, infinity).

% @doc adds a player to a table
add_player(Table, Player) ->
	gen_server:cast(Table, {add_player, Player}).

% @doc removes player form a table
remove_player(Table, Player) ->
	call(Table, {remove_player, Player}).

%% @doc Get a list of all player processes attached to this table
get_player_list(TableToken) ->
    TablePid = ggs_coordinator:table_token_to_pid(TableToken),
    gen_server:call(TablePid, get_player_list).

% @doc stops the table process
stop(Table) ->
    gen_server:cast(Table, stop).

% @doc notifies the table with a message from a player
notify(TablePid, Player, Message) ->
    %TablePid = ggs_coordinator:table_token_to_pid(TableToken),
    gen_server:cast(TablePid, {notify, Player, Message}).

notify_all_players(TableToken, Message) ->
    TablePid = ggs_coordinator:table_token_to_pid(TableToken),
    gen_server:cast(TablePid, {notify_all_players, Message}).

notify_game(TablePid, From, Message) ->
    TableToken = ggs_coordinator:table_pid_to_token(TablePid),
    gen_server:cast(TableToken, {notify_game, Message, From}).

%% @doc Notify a player sitting at this table with the message supplied.
%% Player, Table and From are in token form.
send_command(TableToken, PlayerToken, Message) ->
    TablePid = ggs_coordinator:table_token_to_pid(TableToken),
    gen_server:cast(TablePid, {notify_player, PlayerToken, self(), Message}).

already_defined(TablePid) ->
    gen_server:call(TablePid, already_defined).

%% ----------------------------------------------------------------------

%% @private
init([TableToken]) ->
    process_flag(trap_exit, true),
    GameVM = ggs_gamevm:start_link(TableToken),
    {ok, #state { 
		  game_vm = GameVM,
		  players = [],
		  already_defined = false }}.

%% @private

handle_call({remove_player, Player}, _From, #state { players = Players } = State) ->
    {reply, ok, State#state { players = Players -- [Player] }};
    
handle_call(already_defined, _From, #state { already_defined = AlreadyDefined} = State) ->
    {reply, AlreadyDefined, State};

handle_call(get_player_list, _From, #state { players = Players } = State) ->
    TokenPlayers = lists:map(
            fun (Pid) -> ggs_coordinator:player_pid_to_token(Pid) end, Players),
	{reply, {ok, TokenPlayers}, State};

handle_call(get_player_list_raw, _From, #state { players = Players } = State) ->
	{reply, {ok, Players}, State};

handle_call(Msg, _From, State) ->
    error_logger:error_report([unknown_msg, Msg]),
    {reply, ok, State}.

%% @private
handle_cast({notify, Player, Message}, #state { game_vm = GameVM } = State) ->
    PlayerToken = ggs_coordinator:player_pid_to_token(Player),
    case Message of
        {server, define, Args} ->
            ggs_gamevm:define(GameVM, Args),
            NewState = State#state{ already_defined = true };
        {game, Command, Args} ->
            ggs_gamevm:player_command(GameVM, PlayerToken, Command, Args),
            NewState = State
    end,
    {noreply, NewState};

handle_cast({add_player, Player}, #state { players = Players } = State) ->
    {noreply, State#state { players = [Player | Players] }};

handle_cast({notify_game, Message, From}, #state { game_vm = GameVM } = State) ->
    ggs_gamevm:player_command(GameVM, From, Message, ""),
    {noreply, State};

handle_cast({notify_all_players, Message}, #state{players = Players} = State) ->
    lists:foreach(
        fun(P) -> ggs_player:notify(P, "Server", Message) end,
        Players
    ),
    {noreply, State};

handle_cast({notify_player, PlayerToken, From, Message}, State) ->
    PlayerPid = ggs_coordinator:player_token_to_pid(PlayerToken),
    ggs_player:notify(PlayerPid, From, Message),
    {noreply, State};

handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(Msg, S) ->
    error_logger:error_report([unknown_msg, Msg]),
    {noreply, S}.

%% @private
handle_info(Msg, S) ->
    error_logger:error_report([unknown_msg, Msg]),
    {noreply, S}.
    
%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

