-module(p2p_server).

-export([start_link/1, stop/0, init_loop/2]).

-define(SERVER, ?MODULE).
-define(SEPARATOR, <<"\r\n\r\n">>).

-record(state, {table, id, sock}).

start_link(Port) ->
    GlobalState = #state{table = ets:new(p2p_table, [set, public])},
    socket_server:start(?MODULE, Port, {?MODULE, init_loop}, GlobalState).

stop() ->
    socket_server:stop(?MODULE).

init_loop(Socket, GlobalState) ->
    io:format("localInfo: ~p~n", [inet:sockname(Socket)]),
    random:seed(erlang:now()),
    Id = uuid:v4(),
    io:format("id: ~p~n", [uuid:to_string(Id)]),
    loop(GlobalState#state{id = Id, sock = Socket}, <<"">>).

% read until SEPARATOR and remove the ending SEPARATOR
read_cmd(Socket, Buf) ->
    io:format("Buf = ~p~n", [Buf]),
    case gen_tcp:recv(Socket, 0) of
        {ok, RawData} ->
            io:format("RawData= ~p~n", [RawData]),
            NewBuf = <<Buf/binary, RawData/binary>>,
            io:format("newbuf= ~p~n", [NewBuf]),
            case binary:split(NewBuf, ?SEPARATOR) of
                [_Obj] ->
                    read_cmd(Socket, NewBuf);
                [Data, Remain] ->
                    io:format("D: ~p, R:~p~n", [Data, Remain]),
                    {ok, Data, Remain}
            end;
        Error -> Error
    end.


loop(GlobalState, PreBuf) ->
    Table = GlobalState#state.table,
    Socket = GlobalState#state.sock,
    io:format("loop: ~p~n", [GlobalState]),
    case read_cmd(Socket, PreBuf) of
        {ok, Data, RemainBuf} ->
            Cmd = parse_cmd(Data),
            command_handler(Socket, GlobalState, Cmd),
            loop(GlobalState, RemainBuf);
        {error, Reason} ->
            io:format("error: ~p~n", [Reason]),
            ets:delete(Table, GlobalState#state.id),
            ok
    end.

parse_cmd(<<"add ", Remain/binary>>) ->
    io:format("add ~p~n", [Remain]),
    case re:run(Remain, <<"\d*\.\d*\.\d*\.\d*:\d*">>) of
        nomatch -> close; % format error
        _ -> {add, binary_to_list(Remain)}
    end;
parse_cmd(<<"get ", Id/binary>>) ->
    {get, Id};
parse_cmd(<<"list">>) ->
    list;
parse_cmd(_) ->
    close.

command_handler(Socket, _, close) ->
    gen_tcp:close(Socket);

command_handler(Socket, GlobalState, {add, PeerPrivInfo}) ->
    {ok, PeerPubInfo} = inet:peername(Socket),
    PeerPubInfoStr = addr_to_str(PeerPubInfo),
    Table = GlobalState#state.table,
    Id = GlobalState#state.id,
    io:format("PeerPrivateInfo: ~p~n", [PeerPrivInfo]),
    io:format("PeerPublicInfo: ~p~n", [PeerPubInfo]),
    ets:insert(Table, {Id, {PeerPubInfoStr, PeerPrivInfo}}),
    gen_tcp:send(Socket, <<"ok\r\n\n">>);

command_handler(Socket, GlobalState, list) ->
    Table = GlobalState#state.table,
    Reply = ets:foldl(fun({Id, {PeerPubInfo, PeerPrivInfo}}, Acc) ->
                io:format("Id:~p, Pub:~p, Priv:~p~n", [Id, PeerPubInfo, PeerPrivInfo]),
                uuid:to_string(Id) ++ " " ++ PeerPubInfo
                                   ++ "," ++ PeerPrivInfo
                                   ++ "\r\n" ++ Acc
            end, "", Table),
    ReplyBin = list_to_binary(Reply),
    gen_tcp:send(Socket, <<ReplyBin/binary, "\r\n">>);

command_handler(Socket, GlobalState, {get, Id}) ->
    Table = GlobalState#state.table,
    ID = uuid:to_binary(binary_to_list(Id)),
    io:format("ID: ~p~n", [ID]),
    Reply = case ets:lookup(Table, ID) of
        [{_, {PeerPubInfo, PeerPrivInfo}}] ->
            PeerPubInfo ++ "," ++ PeerPrivInfo;
        _ -> "error"
        end,
    ReplyBin = list_to_binary(Reply),
    gen_tcp:send(Socket, <<ReplyBin/binary, "\r\n">>).

ip_to_str({A, B, C, D}) ->
    string:join(
        [integer_to_list(A),
        integer_to_list(B),
        integer_to_list(C),
        integer_to_list(D)], ".");

ip_to_str({A, B, C, D, E, F}) ->
    string:join(
        [integer_to_list(A),
        integer_to_list(B),
        integer_to_list(C),
        integer_to_list(D),
        integer_to_list(E),
        integer_to_list(F)], ".").

addr_to_str({Addr, Port}) ->
    ip_to_str(Addr) ++ ":" ++ integer_to_list(Port).

