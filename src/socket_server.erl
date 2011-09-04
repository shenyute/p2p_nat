-module(socket_server).
-author('Jesse E.I. Farmer <jesse@20bits.com>').
-behavior(gen_server).

-export([init/1, code_change/3, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-export([accept_loop/1]).
-export([start/4, stop/1]).

-define(TCP_OPTIONS, [binary, {packet, 0}, {active, false}, {reuseaddr, true}]).

-record(server_state, {
        port,
        loop,
        ip=any,
        lsocket=null,
        global_state
    }).

start(Name, Port, Loop, GlobalState) ->
    State = #server_state{port = Port, loop = Loop, global_state = GlobalState},
    gen_server:start_link({local, Name}, ?MODULE, State, []).

stop(Name) ->
    io:format("call stop ~p~n", [?MODULE]),
    gen_server:cast(Name, stop).

init(State = #server_state{port=Port}) ->
    process_flag(trap_exit, true),
    case gen_tcp:listen(Port, ?TCP_OPTIONS) of
        {ok, LSocket} ->
            NewState = State#server_state{lsocket = LSocket},
            {ok, accept(NewState)};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_cast({accepted, _Pid}, State) ->
    {noreply, accept(State)};
handle_cast(stop, State) ->
    io:format("stop~n"),
    {stop, normal, State}.

accept_loop({Server, LSocket, {M, F}, GlobalState}) ->
    {ok, Socket} = gen_tcp:accept(LSocket),
    % Let the server spawn a new process and replace this loop
    % with the client loop, to avoid blocking
    gen_server:cast(Server, {accepted, self()}),
    io:format("Server:~p, M:~p F:~p Socket:~p~n", [Server, M, F, Socket]),
    % the client handler can update global state
    apply(M, F, [Socket, GlobalState]).

% To be more robust we should be using spawn_link and trapping exits
accept(State = #server_state{lsocket=LSocket, loop = Loop, global_state = GlobalState}) ->
    proc_lib:spawn_link(?MODULE, accept_loop, [{self(), LSocket, Loop, GlobalState}]),
    State.

% These are just here to suppress warnings.
handle_call(_Msg, _Caller, State) -> {noreply, State}.
handle_info(_Msg, Library) ->
    io:format("info: ~p~n", [_Msg]),
    {noreply, Library}.
terminate(_Reason, _Library) -> ok.
code_change(_OldVersion, Library, _Extra) -> {ok, Library}.
