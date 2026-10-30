# Compact single-user lab. See GitLab's memory-constrained environments guide.
external_url 'http://gitlab.local:EXTERNAL_PORT_PLACEHOLDER'
nginx['listen_port'] = 80
nginx['listen_https'] = false
letsencrypt['enable'] = false
puma['worker_processes'] = 0
puma['min_threads'] = 1
puma['max_threads'] = 2
sidekiq['concurrency'] = 5
postgresql['shared_buffers'] = '128MB'
prometheus_monitoring['enable'] = false
gitlab_kas['enable'] = false
gitlab_rails['gitlab_kas_enabled'] = false
registry['enable'] = false
gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16']
