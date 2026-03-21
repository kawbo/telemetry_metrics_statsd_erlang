%% @doc Telemetry event handler attachment and dispatch.
%% Mirrors TelemetryMetricsStatsd.EventHandler.
%%
%% Handlers run *inline in the calling process* (telemetry semantics):
%% no message passing on the hot path.
-module(tms_event_handler).
-include("telemetry_metrics_statsd.hrl").

-export([attach/7, detach/1, handle_event/4]).

-type handler_id() :: term().
-type handler_config() :: #{
    reporter    := pid(),
    pool_id     := ets:tid(),
    metrics     := [tms_metric:t()],
    mtu         := pos_integer(),
    prefix      := tms_formatter:prefix(),
    formatter   := tms_formatter:formatter(),
    global_tags := [{atom(), term()}]
}.

-export_type([handler_id/0]).

%% @doc Attach telemetry handlers for each unique event_name in Metrics.
%% Returns a list of handler IDs (one per unique event_name).
-spec attach([tms_metric:t()], pid(), ets:tid(), pos_integer(),
             tms_formatter:prefix(), tms_formatter:formatter(),
             [{atom(), term()}]) -> [handler_id()].
attach(Metrics, Reporter, PoolId, MTU, Prefix, Formatter, GlobalTags) ->
    %% Group metrics by event_name — one handler per unique event.
    ByEvent = group_by_event(Metrics),
    maps:fold(fun(EventName, EventMetrics, Acc) ->
        HandlerId = handler_id(EventName, Reporter),
        Config = #{
            reporter    => Reporter,
            pool_id     => PoolId,
            metrics     => EventMetrics,
            mtu         => MTU,
            prefix      => Prefix,
            formatter   => Formatter,
            global_tags => GlobalTags
        },
        ok = telemetry:attach(HandlerId, EventName, fun ?MODULE:handle_event/4, Config),
        [HandlerId | Acc]
    end, [], ByEvent).

%% @doc Detach a list of handler IDs.
-spec detach([handler_id()]) -> ok.
detach(HandlerIds) ->
    lists:foreach(fun telemetry:detach/1, HandlerIds).

%% @doc Telemetry handler callback — called in the process that executes the event.
-spec handle_event([atom()], map(), map(), handler_config()) -> ok.
handle_event(_EventName, Measurements, Metadata, #{
        reporter    := Reporter,
        pool_id     := PoolId,
        metrics     := Metrics,
        mtu         := MTU,
        prefix      := Prefix,
        formatter   := Formatter,
        global_tags := GlobalTags
    }) ->
    Packets = lists:filtermap(fun(Metric) ->
        case keep(Metric, Metadata) of
            false ->
                false;
            true ->
                case fetch_measurement(Metric, Measurements, Metadata) of
                    undefined ->
                        false;
                    Value ->
                        TagValuesMap = maps:merge(
                            maps:from_list(GlobalTags),
                            (Metric#metric.tag_values)(Metadata)
                        ),
                        Tags = [{Tag, maps:get(Tag, TagValuesMap, <<>>)}
                                || Tag <- Metric#metric.tags],
                        Packet = tms_formatter:format(Formatter, Metric, Prefix, Value, Tags),
                        {true, Packet}
                end
        end
    end, Metrics),
    case Packets of
        [] -> ok;
        _  -> publish(Reporter, PoolId, tms_packet:build_packets(Packets, MTU, <<"\n">>))
    end.

%% ------------------------------------------------------------------ private

-spec keep(tms_metric:t(), map()) -> boolean().
keep(#metric{keep = undefined}, _Metadata) -> true;
keep(#metric{keep = KeepFn}, Metadata)     -> KeepFn(Metadata).

%% Sample check: returns the measurement key/fun, or undefined when outside sample rate.
-spec sample(tms_metric:t()) -> atom() | fun() | undefined.
sample(#metric{reporter_options = Opts, measurement = Measurement}) ->
    Rate = proplists:get_value(sampling_rate, Opts, 1.0),
    case Rate of
        1.0 -> Measurement;
        _   ->
            case rand:uniform() =< Rate of
                true  -> Measurement;
                false -> undefined
            end
    end.

-spec fetch_measurement(tms_metric:t(), map(), map()) -> number() | undefined.
fetch_measurement(#metric{type = counter} = Metric, _Measurements, _Metadata) ->
    case sample(Metric) of
        undefined -> undefined;
        _         -> 0
    end;
fetch_measurement(Metric, Measurements, Metadata) ->
    case sample(Metric) of
        undefined ->
            undefined;
        Fun when is_function(Fun, 1) ->
            value_or_undefined(Fun(Measurements));
        Fun when is_function(Fun, 2) ->
            value_or_undefined(Fun(Measurements, Metadata));
        Key when is_atom(Key) ->
            value_or_undefined(maps:get(Key, Measurements, undefined))
    end.

-spec value_or_undefined(term()) -> number() | undefined.
value_or_undefined(V) when is_number(V) -> V;
value_or_undefined(_)                   -> undefined.

-spec publish(pid(), ets:tid(), [binary()]) -> ok.
publish(Reporter, PoolId, Packets) ->
    case telemetry_metrics_statsd:get_udp(PoolId) of
        {ok, Udp} ->
            lists:foldl(fun
                (Packet, cont) ->
                    case tms_udp:send(Udp, Packet) of
                        ok             -> cont;
                        {error, Reason} ->
                            telemetry_metrics_statsd:udp_error(Reporter, Udp, Reason),
                            halt
                    end;
                (_Packet, halt) ->
                    halt
            end, cont, Packets),
            ok;
        error ->
            ok
    end.

-spec group_by_event([tms_metric:t()]) -> #{[atom()] => [tms_metric:t()]}.
group_by_event(Metrics) ->
    lists:foldl(fun(#metric{event_name = EN} = M, Acc) ->
        Existing = maps:get(EN, Acc, []),
        maps:put(EN, Existing ++ [M], Acc)
    end, #{}, Metrics).

-spec handler_id([atom()], pid()) -> handler_id().
handler_id(EventName, Reporter) ->
    {?MODULE, Reporter, EventName}.
