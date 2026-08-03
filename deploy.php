<?php

/**
 * Deployer configuration — https://deployer.org
 *
 * The release artifact is built in GitHub Actions (composer install + the
 * Quasar PWA build) and uploaded here ready to run. Nothing is compiled on the
 * VPS beyond the php image itself.
 *
 * Everything environment-specific comes from the environment: DEPLOY_HOST,
 * DEPLOY_USER, DEPLOY_PATH, HEALTHCHECK_URL. Set them as GitHub secrets.
 *
 * Layout under DEPLOY_PATH on the server:
 *
 *   <DEPLOY_PATH>/
 *   ├── releases/<n>/     code + back/vendor + front/dist/pwa
 *   ├── shared/           .env files, Laravel storage, postgres data
 *   └── current -> releases/<n>
 *
 * Note that host nginx never reads these paths — it only proxies to
 * 127.0.0.1:8000 and :8080 — so no nginx config depends on `current`.
 */

namespace Deployer;

require 'recipe/common.php';

// Same value compose uses, so the skeleton carries no project identity.
set('application', getenv('COMPOSE_PROJECT_NAME') ?: 'app');
set('keep_releases', 2);   // current + one to roll back to; each release is ~100 MB

set('artifact', 'build/release.tar.gz');

set('shared_files', ['.env']);
set('shared_dirs', []);

// Shared dirs are already owned by the deploy user; skip the ACL/chmod pass.
set('writable_dirs', []);

set('compose_services', 'nginx php postgres');

set('compose_up', 'docker compose up -d --build {{compose_services}}');
set('compose_timeout', 1800);

$healthcheckUrl = getenv('HEALTHCHECK_URL');

if (! $healthcheckUrl) {
    throw new \RuntimeException(
        'HEALTHCHECK_URL is not set. Export the full health endpoint before running dep, '
        . 'e.g. HEALTHCHECK_URL=https://app.example.com/api/health dep deploy production'
    );
}

set('health_url', $healthcheckUrl);

set('artisan', 'docker compose exec -T -e HOME=/tmp php php artisan');

$deployHost = getenv('DEPLOY_HOST');

if (! $deployHost) {
    throw new \RuntimeException(
        'DEPLOY_HOST is not set. Export the server hostname or IP before running dep, '
        . 'e.g. DEPLOY_HOST=203.0.113.10 dep deploy production'
    );
}

$deployUser = getenv('DEPLOY_USER');

if (! $deployUser) {
    throw new \RuntimeException(
        'DEPLOY_USER is not set. Export the SSH user before running dep, '
        . 'e.g. DEPLOY_USER=deploy dep deploy production'
    );
}

$deployPath = getenv('DEPLOY_PATH');

if (! $deployPath) {
    throw new \RuntimeException(
        'DEPLOY_PATH is not set. Export the deploy directory before running dep, '
        . 'e.g. DEPLOY_PATH=~/www/myapp dep deploy production'
    );
}

host('production')
    ->setHostname($deployHost)
    ->setRemoteUser($deployUser)
    ->setDeployPath($deployPath);

/* -------------------------------------------------------------------------
 * Artifact upload, replacing the default git clone
 * ---------------------------------------------------------------------- */

desc('Upload and unpack the CI-built artifact');
task('deploy:update_code', function () {
    upload(get('artifact'), '{{release_path}}/release.tar.gz');
    run('cd {{release_path}} && tar -xzf release.tar.gz && rm release.tar.gz');
});

/* -------------------------------------------------------------------------
 * Docker
 * ---------------------------------------------------------------------- */

desc('Start the new release containers');
task('deploy:compose', function () {
    run('cd {{release_path}} && {{compose_up}}', timeout: (int) get('compose_timeout'));
});

desc('Verify the shipped vendor matches the runtime PHP');
task('deploy:check_platform', function () {
    run('cd {{release_path}} && docker compose exec -T -e HOME=/tmp php composer check-platform-reqs --no-dev');
});

desc('Run database migrations');
task('deploy:migrate', function () {
    run('cd {{release_path}} && {{artisan}} migrate --force');
});

desc('Build Laravel bootstrap caches');
task('deploy:optimize', function () {
    run('cd {{release_path}} && {{artisan}} optimize');
});

desc('Verify the deployed app answers');
task('deploy:health', function () {
    run('curl -fsS --max-time 15 -o /dev/null {{health_url}}');
});

/* -------------------------------------------------------------------------
 * Flow
 * ---------------------------------------------------------------------- */

desc('Deploy the application');
task('deploy', [
    'deploy:prepare',   // info, setup, lock, release, update_code, shared, writable
    'deploy:compose',
    'deploy:check_platform',
    'deploy:migrate',
    'deploy:optimize',
    'deploy:health',
    'deploy:publish',   // symlink, unlock, cleanup, success
]);

after('deploy:failed', 'deploy:unlock');

desc('Bring the containers up on whatever `current` points at');
task('compose:current', function () {
    if (test('[ -L {{deploy_path}}/current ]')) {
        run('cd {{deploy_path}}/current && {{compose_up}}', timeout: (int) get('compose_timeout'));
    } else {
        writeln('No previous release to fall back to — leaving containers as they are.');
    }
});

after('deploy:failed', 'compose:current');
after('rollback', 'compose:current');
