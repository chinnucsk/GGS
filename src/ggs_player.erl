-module(ggs_player).
-export([start_link/1, notify/3, get_token/1, stop/2]).
-record(pl_state,
        {token,         % Player's token
         socket,        % Player's socket
         table}).      % Player's table

%% @doc This module handles communication between a player and GGS. This module is
%%responsible for: 
%% * The storage of the player socket, player token and a table token.
%% * Ability to fetch a player token.
%% * Forwarding messages from players to the game
%% * Remove a player from GGS

%% @doc Spawns a process representing the player in GGS. Takes the player socket as
%% an argument for storage and later usage. Creates a unique player token
%% identifying the player.
%% @spec start_link(Socket::socket()) -> {ok, Pid} | {error, Reason}
start_link(Socket) -> 
    % The socket is in 'active' mode, and that means we are pushed any data
    % that arrives on it, we do not need to recv() manually. Since the socket
    % was opened in our parent process, we need to change the owner of it to
    % us, otherwise these messages end up in our parent.
    erlang:port_connect(Socket, self()),
    {ok, Token} = ggs_coordinator:join_lobby(),
    TableStatus = ggs_coordinator:join_table(1337),
    case TableStatus of
        {ok, Table} ->
            loop(#pl_state{socket = Socket, token = Token, table = Table});
        {error, no_such_table} ->
            ggs_coordinator:create_table({force, 1337}),
            {ok, Table} = ggs_coordinator:join_table(1337),
            loop(#pl_state{socket = Socket, token = Token, table = Table})
    end.

%% @doc Handles incoming messages from the GGS and forwards them through the player
%% socket to the player.
%% @spec notify(Player::Pid(), From::Pid(), 
%%              {Command::String(), Message::string()}) -> ok
notify(Player, From, Message) ->
    Player ! {notify, From, Message}.

%% @doc Get the player token uniquely representing the player.
%% @spec get_token() -> string()
get_token(_Player) ->
    ggs_logger:not_implemented().

%% @doc Properly terminates the player process. The player token will be lost
%% together with the table token. It should also close the player socket and the 
%% process should return in the end.
%% @spec stop(Table::pid()) -> Reason::string()
stop(_Player,_Table) ->
    ggs_logger:not_implemented().

%% Internals

loop(#pl_state{token = Token, socket = Socket, table = Table} = State) ->
    receive 
        {tcp, Socket, Data} -> % Just echo for now..
            io:format("Notifying table..~n"),
            ggs_table:notify_game(Table, Token, Data),
            loop(State);
        {notify, From, Message} ->
            gen_tcp:send(Socket, Message),
            loop(State)
    end.
