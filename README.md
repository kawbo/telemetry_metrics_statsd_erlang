# telemetry_metrics_statsd (Erlang)

Vibecodded Erlang port of [`telemetry_metrics_statsd`](https://github.com/beam-telemetry/telemetry_metrics_statsd) — a [Telemetry](https://github.com/beam-telemetry/telemetry) reporter that publishes metrics to StatsD over UDP.

## Overview

This library provides metric constructors and a `gen_server` reporter that:

- Manages a pool of UDP sockets in an ETS table
- Attaches telemetry handlers for each configured metric's event
- Formats metrics using the standard StatsD or Datadog tag format
- Handles socket errors and optional periodic DNS re-resolution
- Packs multiple metrics into MTU-sized datagrams

The implementation is 1-to-1 with the original Elixir library, excluding Elixir-specific features such as `NimbleOptions` validation.

## Usage

```erlang
Metrics = [
    telemetry_metrics_statsd:counter(<<"http.request.count">>),
    telemetry_metrics_statsd:last_value(<<"vm.memory.total">>),
    telemetry_metrics_statsd:summary(<<"http.request.latency">>)
],
{ok, _} = telemetry_metrics_statsd:start_link([
    {metrics,     Metrics},
    {host,        "statsd.local"},
    {port,        8125},
    {formatter,   datadog},
    {prefix,      <<"myapp">>},
    {pool_size,   4},
    {global_tags, [{env, <<"prod">>}]}
]).
```

## Metric Types

| Constructor      | StatsD type | Wire suffix |
|------------------|-------------|-------------|
| `counter/1,2`    | Counter     | `\|c`        |
| `sum/1,2`        | Gauge       | `\|g`        |
| `last_value/1,2` | Gauge       | `\|g`        |
| `summary/1,2`    | Timer       | `\|ms`       |
| `distribution/1,2` | Timer     | `\|ms`       |

## Options

| Option                     | Default         | Description |
|----------------------------|-----------------|-------------|
| `metrics`                  | required        | List of metric definitions |
| `host`                     | `{127,0,0,1}`   | StatsD host (string or IP tuple) |
| `port`                     | `8125`          | StatsD port |
| `socket_path`              | —               | Unix domain socket path (overrides host/port) |
| `formatter`                | `standard`      | `standard` or `datadog` |
| `global_tags`              | `[]`            | Tags added to every metric |
| `prefix`                   | —               | Prefix prepended to all metric names |
| `pool_size`                | `10`            | Number of UDP sockets in the pool |
| `mtu`                      | `512`           | Maximum datagram size in bytes |
| `inet_address_family`      | `inet`          | `inet` or `inet6` |
| `host_resolution_interval` | —               | DNS re-resolution interval in ms |

## Formatters

### Standard

Tags are appended as dot-separated segments of the metric name. An empty tag value causes the metric to be dropped.

```
http.request.count.prod.GET.200:1|c
```

### Datadog

Tags are appended as `|#key:value` pairs.

```
http.request.count:1|c|#env:prod,method:GET,status:200
```

## Sampling

```erlang
telemetry_metrics_statsd:counter(<<"http.requests">>, [
    {reporter_options, [{sampling_rate, 0.1}]}
])
```

## Building

```sh
make compile
make eunit
make dialyze
```

## Original Library

This is a port of [`beam-telemetry/telemetry_metrics_statsd`](https://github.com/beam-telemetry/telemetry_metrics_statsd), which is the canonical Elixir implementation.
