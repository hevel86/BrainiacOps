<?php
for ($attempt = 0; $attempt < 80; $attempt++) {
    $context = stream_context_create(['http' => ['timeout' => 5, 'ignore_errors' => true, 'follow_location' => 0]]);
    $raw = @file_get_contents('http://127.0.0.1:8080/health.php', false, $context);
    $record = $raw === false ? null : json_decode($raw, true);
    if (is_array($record) && !empty($record['runtimeVerified'])) {
        echo 'FPM_RUNTIME_CHECK ', json_encode($record), PHP_EOL;
        exit(0);
    }
    sleep(3);
}
fwrite(STDERR, "FPM runtime verification failed; refusing to start cron\n");
exit(1);
