%% @doc Type definitions for metric types and related helpers.
-module(tms_metric).
-include("telemetry_metrics_statsd.hrl").

-export_type([type/0, t/0]).

-type type() :: counter | last_value | sum | summary | distribution.
-type t()    :: #metric{}.
