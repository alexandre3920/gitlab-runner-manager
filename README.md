# Gitlab-runner manager

`Bash` script created to manage (register, unregister, start, stop) `gitlab-runner` running on CI environment. Runners are launched using `docker` and the `gitlab/gitlab-runner` Docker image. Therefor it is required to have `docker` install on the host.

It can be used with a on-premise Gitlab instance, accessible with a self-signed certificate (`-a` option) or not.

> Note the CA certificate file must be in PEM format (ie. starting with the -----BEGIN CERTIFICATE----- header)

## Configuration

The `.conf` config file must respect a specfic format:

```bash
gitlab_conf_url=gitlab url
gitlab_conf_token=gitlab runner registration token
gitlab_conf_repository_name=repository name
gitlab_conf_description=Runner for django-doctor-dashboard
gitlab_conf_runner_version=latest
gitlab_conf_tags=docker,python
```

> - `gitlab_conf_url`: (REQUIRED) the url of your Gitlab instance
> - `gitlab_conf_token`: (REQUIRED) the token to register your runner (from CI/CD > Runner configuration)
> - `gitlab_conf_repository_name`: (REQUIRED) the name of your Gitlab repository. This value will be used to set:
>   1. the name of the runner `gitlab-runner-{host_name}-{repository_name}`
>   2. the name of the docker volume attached to the runner `gitlab-runner-{repository_name}-volume`
> - `description`: (OPTIONAL) if you want to set a custom description for your runner. If not submited, a default description value will be set `Runner for {repository_name} on {host_name}`
> - `gitlab_conf_runner_version`: (OPTIONAL) if you want to set a custom version for your runner. If not submited, the default value used is `latest`.
> - `gitlab_conf_tags`: (OPTIONAL) if you want to set a custom list of tags separated by comma to your runner. If not submited, a default `docker` tag will be set.

You can find an example config file in this repository [example.conf](example.conf).

## Usage

```bash
$ ./gitlab-runner.sh [OPTIONS] -c CONFIG_FILE COMMAND

Options
    -h                  display the help
    -a CA_CERT_FILE     path to the CA certificate file

Configurations
    -c CONFIG_FILE      path to the config file

Commands
    register            register a new runner
    unregister          unregister a runner
    list                list registered runners
    start               start the runner
    stop                stop a runner
```

1. register

```bash
./gitlab-runner.sh [-a ca-cert.crt] -c example.conf register
```

This command will register a new runner for your Gitlab instance, named `Runner for {repository_name} on {host_name}`. Once the runner is registered you should be able to see it in Gitlab > CI/CD > Runners, and then start it.

When you register a new runner, a new docker volume named  is created. This container will contain the `config.toml` file for the runner, and if used the `ca.crt` file if you use an internal CA.

2. start

```bash
./gitlab-runner.sh [-a ca-cert.crt] -c example.conf start
```

This command start the runner by running a new docker container. Before running the container, a docker volume is created named `gitlab-runner-{gitlab_conf_repository_name}-volume`. Then a container named `gitlab-runner-{host_name}-{gitlab_conf_repository_name}` is launch.

You can configure the version of the runner in the config file with the `runner_version` parameter.

3. stop

```bash
./gitlab-runner.sh [-a ca-cert.crt] -c example.conf stop
```

This command stop the runner (ie. the container) named `gitlab-runner-{host_name}-{gitlab_conf_repository_name}`.

4. unregister

```bash
./gitlab-runner.sh [-a ca-cert.crt] -c example.conf unregister [-t RUNNER_TOKEN|-a]
```

This command will unregister a specific runner or all runners. Use `-t RUNNER_TOKEN` to unregister a specific runner or `-a` to unregister all runners.
