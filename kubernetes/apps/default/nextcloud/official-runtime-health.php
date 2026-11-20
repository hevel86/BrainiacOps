<?php
header('Content-Type: application/json');
$result = [
    'phpVersion' => PHP_VERSION,
    'sapi' => PHP_SAPI,
    'uid' => posix_geteuid(),
    'uploadProgressEnabled' => ini_get('session.upload_progress.enabled'),
    'memoryLimit' => ini_get('memory_limit'),
    'uploadLimit' => ini_get('upload_max_filesize'),
    'postLimit' => ini_get('post_max_size'),
    'apcuLoaded' => extension_loaded('apcu'),
    'pdoMysqlLoaded' => extension_loaded('pdo_mysql'),
];
$ok = version_compare(PHP_VERSION, '8.4.28', '>=') && PHP_SAPI === 'fpm-fcgi'
    && $result['uid'] === 1000 && in_array($result['uploadProgressEnabled'], ['', '0'], true)
    && $result['memoryLimit'] === '-1' && $result['apcuLoaded'] && $result['pdoMysqlLoaded'];
http_response_code($ok ? 200 : 503);
echo json_encode(['runtimeVerified' => $ok] + $result), PHP_EOL;
