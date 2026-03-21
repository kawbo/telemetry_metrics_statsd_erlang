%% @doc UDP socket wrapper — mirrors TelemetryMetricsStatsd.UDP.
-module(tms_udp).
-include("telemetry_metrics_statsd.hrl").

-export([open/1, send/2, close/1, update/3]).

-export_type([t/0, config/0]).

-type t() :: #tms_udp{}.

-type config() :: #{
    host                := inet:ip_address() | {local, string()},
    port                => inet:port_number(),
    inet_address_family => inet | inet6
}.

%% @doc Open a new UDP socket from a config map.
-spec open(config()) -> {ok, t()} | {error, term()}.
open(Config) ->
    BaseOpts = [{active, false}],
    Host = maps:get(host, Config),
    Opts0 = case Host of
        {local, _} -> [local | BaseOpts];
        _          -> BaseOpts
    end,
    Opts = case maps:get(inet_address_family, Config, inet) of
        inet  -> Opts0;
        inet6 -> [inet6 | Opts0];
        local -> Opts0
    end,
    case gen_udp:open(0, Opts) of
        {ok, Socket} ->
            Udp = #tms_udp{
                host   = Host,
                port   = maps:get(port, Config, 0),
                socket = Socket
            },
            {ok, Udp};
        {error, _} = Err ->
            Err
    end.

%% @doc Send data over UDP.
-spec send(t(), iodata()) -> ok | {error, term()}.
send(#tms_udp{host = {local, _} = Host, socket = Socket}, Data) ->
    gen_udp:send(Socket, Host, 0, Data);
send(#tms_udp{host = Host, port = Port, socket = Socket}, Data) ->
    gen_udp:send(Socket, Host, Port, Data).

%% @doc Close the UDP socket.
-spec close(t()) -> ok.
close(#tms_udp{socket = Socket}) ->
    gen_udp:close(Socket).

%% @doc Return a new tms_udp record with updated host and port.
-spec update(t(), inet:ip_address(), inet:port_number()) -> t().
update(#tms_udp{} = Udp, NewHost, NewPort) ->
    Udp#tms_udp{host = NewHost, port = NewPort}.
