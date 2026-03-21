%% @doc MTU-aware UDP packet builder — mirrors TelemetryMetricsStatsd.Packet.
%%
%% Packs a list of binaries into as-large-as-possible datagrams
%% (joined by Joiner) without exceeding MaxSize bytes each.
-module(tms_packet).

-export([build_packets/3]).

-spec build_packets([binary()], pos_integer(), binary()) -> [binary()].
build_packets([], _MaxSize, _Joiner) -> [];
build_packets(Binaries, MaxSize, Joiner)
        when is_integer(MaxSize), MaxSize > 0, is_binary(Joiner) ->
    JoinerSize = byte_size(Joiner),
    build_packets(Binaries, MaxSize, Joiner, JoinerSize, [], 0, 0, []).

-spec build_packets([binary()], pos_integer(), binary(), non_neg_integer(),
                    [binary()], non_neg_integer(), non_neg_integer(), [binary()]) -> [binary()].

%% No more binaries — flush the current accumulator (if non-empty).
build_packets([], _Max, _Joiner, _JS, [], _CurCount, _CurSize, Done) ->
    lists:reverse(Done);
build_packets([], _Max, Joiner, _JS, CurBins, _CurCount, _CurSize, Done) ->
    Packet = join(lists:reverse(CurBins), Joiner),
    lists:reverse([Packet | Done]);

build_packets([Bin | Rest], Max, Joiner, JS, CurBins, CurCount, CurSize, Done) ->
    BinSize = byte_size(Bin),
    NewCount = CurCount + 1,
    NewSize  = CurSize + BinSize,
    %% Total packet size including joiner separators between binaries
    PacketSize = NewSize + (NewCount - 1) * JS,
    if
        PacketSize =< Max ->
            %% Fits — add to current accumulator
            build_packets(Rest, Max, Joiner, JS, [Bin | CurBins], NewCount, NewSize, Done);
        CurBins =:= [] ->
            %% Single binary exceeds MTU — raise, matching Elixir behaviour.
            error({packet_too_large, BinSize, Max});
        true ->
            %% Doesn't fit — flush current accumulator, start new one with Bin
            Packet = join(lists:reverse(CurBins), Joiner),
            build_packets([Bin | Rest], Max, Joiner, JS, [], 0, 0, [Packet | Done])
    end.

-spec join([binary()], binary()) -> binary().
join([], _Joiner)        -> <<>>;
join([Bin], _Joiner)     -> Bin;
join(Bins, Joiner) ->
    iolist_to_binary(lists:join(Joiner, Bins)).
