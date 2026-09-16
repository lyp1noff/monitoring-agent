# monitoring-agent

A small Docker Compose template that sends Linux host metrics from Grafana Alloy to a Prometheus remote-write receiver. It collects CPU, memory, disk, filesystem, and network metrics. This first version does not use the Docker socket or cAdvisor.

## Requirements

- A Linux server with Docker Engine, Docker Compose v2, and Git.
- Permission to run Docker commands.
- Host udev data at `/run/udev/data`.
- Network access to your Prometheus remote-write endpoint. Prometheus must run with `--web.enable-remote-write-receiver`.

## Install on a new server

Run this command on a new server:

```bash
curl -fsSL https://raw.githubusercontent.com/lyp1noff/monitoring-agent/main/install.sh | \
  bash -s -- --hostname web-01 --environment production --site london --role web \
  --prometheus-url http://prometheus.example.com:9090/api/v1/write
```

Replace `prometheus.example.com` with your receiver's real address. The URL in `.env.example` is only a placeholder; the installer rejects it. The script clones the repository into `./monitoring-agent`, creates `.env` and `data/`, then starts Alloy with `docker compose up -d`. Set `MONITORING_AGENT_DIR` to use another install directory.

Alternatively, clone the repository yourself and run `./install.sh` from the checkout. Missing arguments are prompted in a terminal. Without a terminal, the script uses values from `.env.example` or an existing `.env`; you must still supply a real Prometheus URL.

Alloy listens on `127.0.0.1:12345` by default. To use a different local port, edit `ALLOY_HTTP_LISTEN_ADDR` in `.env` and run `docker compose up -d`. The installer preserves this setting on later runs. The address must stay on `127.0.0.1`.

## Verify

```bash
cd monitoring-agent
docker compose ps
docker compose logs --tail=50 alloy
```

In Prometheus or Grafana Explore, query:

```promql
node_uname_info{instance="web-01",environment="production",site="london",role="web"}
```

Then check `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_filesystem_avail_bytes`, and `node_network_receive_bytes_total` with the same `instance`. Allow about a minute for the first samples.

Check `curl http://127.0.0.1:12345/-/ready` on the server. From your workstation, use `ssh -L 12345:127.0.0.1:12345 user@server` and open `http://127.0.0.1:12345/` locally. Adjust the port in these commands if you changed it in `.env`.

## Maintenance

`.env` contains the four metric labels, the remote-write URL, and the local UI address. It is ignored by Git, as is the persistent `data/` directory. Give each server a unique `INSTANCE` to avoid merging time series.

The container shares the host network and PID namespaces. It mounts host `/proc`, `/sys`, the root filesystem, and udev data read-only. Its only writable mount is `./data` for Alloy state. No Docker port is published.

After editing `.env` or `config.alloy`, apply changes with `docker compose up -d`. Running the download command again updates an existing checkout with `git pull --ff-only` before installing. To stop Alloy, run `docker compose down`; `.env` and `data/` remain in place.
