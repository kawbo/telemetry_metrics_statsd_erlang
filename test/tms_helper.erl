%% @doc Test helpers — mirrors TelemetryMetricsStatsd.Test.Helpers + test utilities.
-module(tms_helper).
-include_lib("../include/telemetry_metrics_statsd.hrl").

-export([
    given_udp_port_opened/0, given_udp_port_opened/1,
    given_unix_socket_opened/0,
    start_reporter/1,
    stop_reporter/1,
    assert_reported/2,
    refute_reported/1,
    %% metric constructors
    given_counter/1, given_counter/2,
    given_sum/1, given_sum/2,
    given_last_value/1, given_last_value/2,
    given_summary/1, given_summary/2,
    given_distribution/1, given_distribution/2,
    %% polling helper
    eventually/1, eventually/2
]).

%% ------------------------------------------------------------------ UDP helpers

-spec given_udp_port_opened() -> {port(), inet:port_number()}.
given_udp_port_opened() ->
    given_udp_port_opened(inet).

-spec given_udp_port_opened(inet | inet6) -> {port(), inet:port_number()}.
given_udp_port_opened(Family) ->
    {ok, Socket} = gen_udp:open(0, [binary, Family, {active, false}]),
    {ok, Port}   = inet:port(Socket),
    {Socket, Port}.

-spec given_unix_socket_opened() -> {port(), string()}.
given_unix_socket_opened() ->
    NameBin  = base16(crypto:strong_rand_bytes(20)),
    Path     = "/tmp/" ++ binary_to_list(NameBin),
    {ok, Socket} = gen_udp:open(0, [binary, local, {active, false},
                                     {ip, {local, Path}}]),
    {Socket, Path}.

base16(Bin) ->
    << <<(hex_char(H)), (hex_char(L))>> || <<H:4, L:4>> <= Bin >>.

hex_char(N) when N < 10 -> $0 + N;
hex_char(N)             -> $a + N - 10.

%% ------------------------------------------------------------------ Reporter

-spec start_reporter([telemetry_metrics_statsd:option()]) -> pid().
start_reporter(Options) ->
    {ok, Pid} = telemetry_metrics_statsd:start_link(Options),
    Pid.

%% @doc Synchronously stop a reporter, waiting for it to fully terminate
%% (and thus detach all telemetry handlers) before returning.
-spec stop_reporter(pid()) -> ok.
stop_reporter(Pid) ->
    Ref = erlang:monitor(process, Pid),
    unlink(Pid),
    exit(Pid, shutdown),
    receive {'DOWN', Ref, process, Pid, _} -> ok end.

%% ------------------------------------------------------------------ Assertions

-spec assert_reported(port(), binary()) -> ok.
assert_reported(Socket, Expected) ->
    Size = byte_size(Expected),
    case gen_udp:recv(Socket, Size, 1000) of
        {ok, {_Host, _Port, Payload}} ->
            case Payload =:= Expected of
                true  -> ok;
                false -> error({unexpected_payload, Payload, expected, Expected})
            end;
        {error, Reason} ->
            error({recv_failed, Reason, expected, Expected})
    end.

-spec refute_reported(port()) -> ok.
refute_reported(Socket) ->
    case gen_udp:recv(Socket, 0, 1000) of
        {error, timeout} ->
            ok;
        {ok, {_Host, _Port, Payload}} ->
            error({unexpected_packet_received, Payload})
    end.

%% ------------------------------------------------------------------ Metric constructors

-spec given_counter(binary()) -> tms_metric:t().
given_counter(Name)       -> telemetry_metrics_statsd:counter(Name).

-spec given_counter(binary(), list()) -> tms_metric:t().
given_counter(Name, Opts) -> telemetry_metrics_statsd:counter(Name, Opts).

-spec given_sum(binary()) -> tms_metric:t().
given_sum(Name)           -> telemetry_metrics_statsd:sum(Name).

-spec given_sum(binary(), list()) -> tms_metric:t().
given_sum(Name, Opts)     -> telemetry_metrics_statsd:sum(Name, Opts).

-spec given_last_value(binary()) -> tms_metric:t().
given_last_value(Name)            -> telemetry_metrics_statsd:last_value(Name).

-spec given_last_value(binary(), list()) -> tms_metric:t().
given_last_value(Name, Opts)      -> telemetry_metrics_statsd:last_value(Name, Opts).

-spec given_summary(binary()) -> tms_metric:t().
given_summary(Name)               -> telemetry_metrics_statsd:summary(Name).

-spec given_summary(binary(), list()) -> tms_metric:t().
given_summary(Name, Opts)         -> telemetry_metrics_statsd:summary(Name, Opts).

-spec given_distribution(binary()) -> tms_metric:t().
given_distribution(Name)          -> telemetry_metrics_statsd:distribution(Name).

-spec given_distribution(binary(), list()) -> tms_metric:t().
given_distribution(Name, Opts)    -> telemetry_metrics_statsd:distribution(Name, Opts).

%% ------------------------------------------------------------------ Polling

%% Poll Fn() up to 2 seconds, returning true when it succeeds.
-spec eventually(fun(() -> boolean())) -> true.
eventually(Fn) -> eventually(Fn, 2000).

-spec eventually(fun(() -> boolean()), non_neg_integer()) -> true.
eventually(Fn, TimeoutMs) ->
    Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
    do_eventually(Fn, Deadline).

do_eventually(Fn, Deadline) ->
    case (catch Fn()) of
        true ->
            true;
        _ ->
            Remaining = Deadline - erlang:monotonic_time(millisecond),
            if
                Remaining =< 0 ->
                    error(eventually_timeout);
                true ->
                    timer:sleep(50),
                    do_eventually(Fn, Deadline)
            end
    end.
