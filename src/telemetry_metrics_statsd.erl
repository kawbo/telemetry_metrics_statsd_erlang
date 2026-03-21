%% @doc Erlang port of TelemetryMetricsStatsd.
%%
%% Provides metric constructors and a GenServer reporter that:
%%  - manages a pool of UDP sockets in an ETS table
%%  - attaches telemetry handlers for each configured metric's event
%%  - handles socket errors and optional periodic DNS re-resolution
%%
%% Usage:
%%   Metrics = [
%%       telemetry_metrics_statsd:counter([http, request, count]),
%%       telemetry_metrics_statsd:last_value([vm, memory, total])
%%   ],
%%   {ok, _} = telemetry_metrics_statsd:start_link([
%%       {metrics,    Metrics},
%%       {host,       "statsd.local"},
%%       {port,       8125},
%%       {formatter,  datadog},
%%       {prefix,     <<"myapp">>},
%%       {pool_size,  4},
%%       {global_tags,[{env, <<"prod">>}]}
%%   ]).

-module(telemetry_metrics_statsd).
-behaviour(gen_server).
-include("telemetry_metrics_statsd.hrl").

%% Metric constructors
-export([
    counter/1, counter/2,
    last_value/1, last_value/2,
    sum/1, sum/2,
    summary/1, summary/2,
    distribution/1, distribution/2
]).

%% Reporter API
-export([start_link/1, child_spec/1]).

%% Internal API used by tms_event_handler and tests
-export([get_pool_id/1, get_udp/1, udp_error/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-define(DEFAULT_HOST,      {127,0,0,1}).
-define(DEFAULT_PORT,      8125).
-define(DEFAULT_POOL_SIZE, 10).
-define(DEFAULT_MTU,       512).
-define(DEFAULT_FORMATTER, standard).

-type option() ::
    {metrics,                  [tms_metric:t()]}
  | {host,                     string() | inet:ip_address()}
  | {port,                     inet:port_number()}
  | {socket_path,              string()}
  | {formatter,                tms_formatter:formatter()}
  | {global_tags,              [{atom(), term()}]}
  | {prefix,                   tms_formatter:prefix()}
  | {pool_size,                pos_integer()}
  | {mtu,                      pos_integer()}
  | {inet_address_family,      inet | inet6}
  | {host_resolution_interval, pos_integer()}.

-type metric_option() ::
    {event_name,       binary() | [atom()]}
  | {measurement,      atom()}
  | {tags,             [atom()]}
  | {tag_values,       fun((map()) -> map())}
  | {keep,             fun((map()) -> boolean())}
  | {drop,             fun((map()) -> boolean())}
  | {reporter_options, list()}.

-export_type([option/0, metric_option/0]).

-record(state, {
    pool_id                  :: ets:tid(),
    handler_ids              :: [tms_event_handler:handler_id()],
    udp_config               :: tms_udp:config(),
    host                     :: string() | inet:ip_address(),
    inet_address_family      :: inet | inet6,
    host_resolution_interval :: pos_integer() | undefined
}).

%% ==================================================================
%% Metric constructors
%% ==================================================================

-spec counter(binary() | [atom()]) -> tms_metric:t().
counter(Name) -> counter(Name, []).

-spec counter(binary() | [atom()], [metric_option()]) -> tms_metric:t().
counter(Name, Opts) -> build_metric(counter, Name, Opts).

-spec last_value(binary() | [atom()]) -> tms_metric:t().
last_value(Name) -> last_value(Name, []).

-spec last_value(binary() | [atom()], [metric_option()]) -> tms_metric:t().
last_value(Name, Opts) -> build_metric(last_value, Name, Opts).

-spec sum(binary() | [atom()]) -> tms_metric:t().
sum(Name) -> sum(Name, []).

-spec sum(binary() | [atom()], [metric_option()]) -> tms_metric:t().
sum(Name, Opts) -> build_metric(sum, Name, Opts).

-spec summary(binary() | [atom()]) -> tms_metric:t().
summary(Name) -> summary(Name, []).

-spec summary(binary() | [atom()], [metric_option()]) -> tms_metric:t().
summary(Name, Opts) -> build_metric(summary, Name, Opts).

-spec distribution(binary() | [atom()]) -> tms_metric:t().
distribution(Name) -> distribution(Name, []).

-spec distribution(binary() | [atom()], [metric_option()]) -> tms_metric:t().
distribution(Name, Opts) -> build_metric(distribution, Name, Opts).

%% ==================================================================
%% Reporter API
%% ==================================================================

-spec child_spec([option()]) -> map().
child_spec(Opts) ->
    #{id => ?MODULE, start => {?MODULE, start_link, [Opts]}}.

-spec start_link([option()]) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    case validate_options(Opts) of
        {ok, Config}      -> gen_server:start_link(?MODULE, Config, []);
        {error, _} = Err  -> Err
    end.

%% @doc Returns the ETS table id for the socket pool.
-spec get_pool_id(pid()) -> ets:tid().
get_pool_id(Reporter) ->
    gen_server:call(Reporter, get_pool_id).

%% @doc Pick a random UDP socket from the pool.
-spec get_udp(ets:tid()) -> {ok, tms_udp:t()} | error.
get_udp(PoolId) ->
    case ets:lookup(PoolId, udp) of
        [] ->
            logger:error("Failed to publish metrics over UDP: no open sockets available."),
            error;
        Entries ->
            {udp, Udp} = lists:nth(rand:uniform(length(Entries)), Entries),
            {ok, Udp}
    end.

%% @doc Report a UDP error for a socket; the GenServer will close and reopen it.
-spec udp_error(pid(), tms_udp:t(), term()) -> ok.
udp_error(Reporter, Udp, Reason) ->
    gen_server:cast(Reporter, {udp_error, Udp, Reason}).

%% ==================================================================
%% gen_server callbacks
%% ==================================================================

-spec init(map()) -> {ok, #state{}}.
init(Config) ->
    process_flag(trap_exit, true),
    Metrics   = maps:get(metrics, Config),
    PoolSize  = maps:get(pool_size, Config),
    MTU       = maps:get(mtu, Config),
    Prefix    = maps:get(prefix, Config),
    Formatter = maps:get(formatter, Config),
    GlobalTags = maps:get(global_tags, Config),
    Host      = maps:get(host, Config),
    InetFam   = maps:get(inet_address_family, Config),
    ResInterval = maps:get(host_resolution_interval, Config, undefined),

    UdpConfig = build_udp_config(Host, maps:get(port, Config), InetFam, ResInterval),

    Udps = [begin {ok, U} = tms_udp:open(UdpConfig), {udp, U} end
            || _ <- lists:seq(1, PoolSize)],

    PoolId = ets:new(?MODULE, [bag, protected, {read_concurrency, true}]),
    ets:insert(PoolId, Udps),

    HandlerIds = tms_event_handler:attach(
        Metrics, self(), PoolId, MTU, Prefix, Formatter, GlobalTags),

    {ok, #state{
        pool_id                  = PoolId,
        handler_ids              = HandlerIds,
        udp_config               = UdpConfig,
        host                     = Host,
        inet_address_family      = InetFam,
        host_resolution_interval = ResInterval
    }}.

-spec handle_call(term(), {pid(), term()}, #state{}) -> {reply, term(), #state{}}.
handle_call(get_pool_id, _From, State) ->
    {reply, State#state.pool_id, State}.

-spec handle_cast(term(), #state{}) -> {noreply, #state{}} | {stop, term(), #state{}}.
handle_cast({udp_error, OldUdp, Reason}, #state{pool_id = PoolId, udp_config = UdpConfig} = State) ->
    OldEntry = {udp, OldUdp},
    case lists:member(OldEntry, ets:lookup(PoolId, udp)) of
        false ->
            %% Already replaced — ignore duplicate error reports
            {noreply, State};
        true ->
            logger:error("Failed to publish metrics over UDP: ~p", [Reason]),
            tms_udp:close(OldUdp),
            ets:delete_object(PoolId, OldEntry),
            case tms_udp:open(UdpConfig) of
                {ok, NewUdp} ->
                    ets:insert(PoolId, {udp, NewUdp}),
                    {noreply, State};
                {error, OpenReason} ->
                    logger:error("Failed to reopen UDP socket: ~p", [OpenReason]),
                    {stop, {udp_open_failed, OpenReason}, State}
            end
    end.

-spec handle_info(term(), #state{}) -> {noreply, #state{}} | {stop, term(), #state{}}.
handle_info(resolve_host, #state{
        host                     = Host,
        inet_address_family      = InetFam,
        host_resolution_interval = Interval,
        pool_id                  = PoolId,
        udp_config               = #{host := CurrentAddr} = UdpConfig
    } = State) ->
    NewState = case inet:gethostbyname(Host, InetFam) of
        {ok, {hostent, _, _, _, _, Addrs}} ->
            case lists:member(CurrentAddr, Addrs) of
                true ->
                    State;
                false ->
                    [NewAddr | _] = Addrs,
                    update_pool(PoolId, NewAddr, maps:get(port, UdpConfig)),
                    State#state{udp_config = UdpConfig#{host => NewAddr}}
            end;
        {error, ResReason} ->
            logger:warning("Failed to resolve hostname ~p: ~p. Using ~p.",
                           [Host, ResReason, CurrentAddr]),
            State
    end,
    erlang:send_after(Interval, self(), resolve_host),
    {noreply, NewState};
handle_info({'EXIT', _Pid, Reason}, State) ->
    {stop, Reason, State};
handle_info(_Msg, State) ->
    {noreply, State}.

-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, #state{handler_ids = HandlerIds}) ->
    tms_event_handler:detach(HandlerIds).

%% ==================================================================
%% Internal helpers
%% ==================================================================

-spec build_udp_config(string() | inet:ip_address(), inet:port_number(),
                        inet | inet6, pos_integer() | undefined) -> tms_udp:config().
build_udp_config({local, _} = LocalHost, Port, _InetFam, _Interval) ->
    #{host => LocalHost, port => Port, inet_address_family => local};
build_udp_config(Host, Port, InetFam, _Interval) when is_tuple(Host) ->
    %% Already an IP address tuple — no DNS resolution needed or scheduled.
    #{host => Host, port => Port, inet_address_family => InetFam};
build_udp_config(Host, Port, InetFam, Interval) ->
    %% Hostname string — resolve once at start
    {ok, {hostent, _, _, _, _, [Ip | _]}} = inet:gethostbyname(Host, InetFam),
    maybe_schedule_resolution(Interval),
    #{host => Ip, port => Port, inet_address_family => InetFam}.

-spec maybe_schedule_resolution(pos_integer() | undefined) -> ok.
maybe_schedule_resolution(undefined) -> ok;
maybe_schedule_resolution(Interval) ->
    erlang:send_after(Interval, self(), resolve_host),
    ok.

-spec update_pool(ets:tid(), inet:ip_address(), inet:port_number()) -> ok.
update_pool(PoolId, NewHost, NewPort) ->
    Entries = ets:tab2list(PoolId),
    lists:foreach(fun({udp, Udp}) ->
        ets:delete_object(PoolId, {udp, Udp}),
        ets:insert(PoolId, {udp, tms_udp:update(Udp, NewHost, NewPort)})
    end, Entries).

%% ------------------------------------------------------------------
%% Metric constructor helper
%% ------------------------------------------------------------------

-spec build_metric(tms_metric:type(), binary() | string() | [atom()], list()) -> tms_metric:t().
build_metric(Type, RawName, Opts) ->
    Name      = parse_name(RawName),
    EventName = parse_event_name(proplists:get_value(event_name, Opts), Name),
    Measurement = case proplists:get_value(measurement, Opts) of
        undefined -> lists:last(Name);
        M         -> M
    end,
    Tags       = proplists:get_value(tags, Opts, []),
    TagValuesFn = case proplists:get_value(tag_values, Opts) of
        undefined -> fun(Meta) -> Meta end;
        Fn        -> Fn
    end,
    Keep = resolve_keep(
        proplists:get_value(keep, Opts),
        proplists:get_value(drop, Opts)
    ),
    ReporterOpts = proplists:get_value(reporter_options, Opts, []),
    #metric{
        type             = Type,
        name             = Name,
        event_name       = EventName,
        measurement      = Measurement,
        tags             = Tags,
        tag_values       = TagValuesFn,
        keep             = Keep,
        reporter_options = ReporterOpts
    }.

-spec parse_name(binary() | string() | [atom()]) -> [atom()].
parse_name(Name) when is_binary(Name) ->
    [binary_to_atom(S, utf8) || S <- binary:split(Name, <<".">>, [global])];
parse_name(Name) when is_list(Name) ->
    case io_lib:printable_list(Name) of
        true  -> [list_to_atom(S) || S <- string:split(Name, ".", all)];
        false -> Name
    end.

-spec parse_event_name(term(), [atom()]) -> [atom()].
parse_event_name(undefined, Name) ->
    lists:droplast(Name);
parse_event_name(EN, _Name) ->
    parse_name(EN).

-spec resolve_keep(term(), term()) -> undefined | fun((map()) -> boolean()).
resolve_keep(undefined, undefined) -> undefined;
resolve_keep(KeepFn,   undefined)  -> KeepFn;
resolve_keep(undefined, DropFn)    -> fun(Meta) -> not DropFn(Meta) end;
resolve_keep(KeepFn,   _DropFn)    -> KeepFn.   % keep takes precedence

%% ------------------------------------------------------------------
%% Option validation
%% ------------------------------------------------------------------

-spec validate_options([option()]) -> {ok, map()} | {error, string()}.
validate_options(Opts) ->
    case proplists:get_value(metrics, Opts) of
        undefined ->
            {error, "missing required option: metrics"};
        Metrics when is_list(Metrics) ->
            Formatter = proplists:get_value(formatter, Opts, ?DEFAULT_FORMATTER),
            case validate_formatter(Formatter) of
                error ->
                    {error, io_lib:format(
                        "invalid value for :formatter option: expected :formatter be either"
                        " :standard or :datadog, got ~s", [format_term(Formatter)])};
                ok ->
                    Config = #{
                        metrics     => Metrics,
                        host        => resolve_host_option(Opts),
                        port        => proplists:get_value(port, Opts, ?DEFAULT_PORT),
                        pool_size   => proplists:get_value(pool_size, Opts, ?DEFAULT_POOL_SIZE),
                        mtu         => proplists:get_value(mtu, Opts, ?DEFAULT_MTU),
                        prefix      => proplists:get_value(prefix, Opts, undefined),
                        formatter   => Formatter,
                        global_tags => proplists:get_value(global_tags, Opts, []),
                        inet_address_family =>
                            proplists:get_value(inet_address_family, Opts, inet),
                        host_resolution_interval =>
                            proplists:get_value(host_resolution_interval, Opts, undefined)
                    },
                    {ok, Config}
            end
    end.

-spec validate_formatter(term()) -> ok | error.
validate_formatter(standard) -> ok;
validate_formatter(datadog)  -> ok;
validate_formatter(_)        -> error.

%% Formats a term for error messages matching Elixir's inspect/1 output for atoms.
-spec format_term(term()) -> iodata().
format_term(T) when is_atom(T) -> [$: | atom_to_list(T)];
format_term(T)                  -> io_lib:format("~p", [T]).

-spec resolve_host_option([option()]) -> inet:ip_address() | string() | {local, string()}.
resolve_host_option(Opts) ->
    case proplists:get_value(socket_path, Opts) of
        undefined ->
            case proplists:get_value(host, Opts, ?DEFAULT_HOST) of
                H when is_binary(H) -> binary_to_list(H);
                H                   -> H
            end;
        Path when is_binary(Path) ->
            {local, binary_to_list(Path)};
        Path when is_list(Path) ->
            {local, Path}
    end.
