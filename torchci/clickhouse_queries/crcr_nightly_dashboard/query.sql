-- Select complete matrix rows before returning their individual jobs. A raw
-- job limit could otherwise cut a many-job nightly in half. The range is
-- qualified by a completed job, then all siblings of the selected SHA/run are
-- returned so an in-progress or older-completed sibling is not lost.
WITH eligible_matrix_keys AS (
    SELECT matrix_key
    FROM (
        SELECT
            if(
                match(pytorch_head_sha, '^[0-9a-fA-F]{40}$'),
                concat('sha:', pytorch_head_sha),
                concat('run:', if(run_id != '', run_id, pytorch_head_sha))
            ) AS matrix_key,
            max(started_at) AS latest_started_at
        FROM default.crcr_workflow_job FINAL
        WHERE
            downstream_repo = {repo: String}
            AND event_type = 'nightly'
            AND status = 'completed'
            AND completed_at >= now() - INTERVAL {days: UInt64} DAY
            AND completed_at < now()
        GROUP BY matrix_key
    )
    ORDER BY latest_started_at DESC, matrix_key DESC
    LIMIT {limit: UInt64} OFFSET {offset: UInt64}
),

deduped AS (
    SELECT
        upstream_repo,
        pytorch_head_sha,
        workflow_name,
        job_name,
        check_run_id,
        run_id,
        run_attempt,
        status,
        conclusion,
        started_at,
        completed_at,
        duration_seconds,
        total_tests,
        passed_tests,
        failed_tests,
        skipped_tests,
        workflow_run_url,
        artifact_url,
        queue_time,
        execution_time,
        failed_tests_json,
        ROW_NUMBER() OVER (
            PARTITION BY pytorch_head_sha, run_id, job_name
            ORDER BY run_attempt DESC
        ) AS rn
    FROM default.crcr_workflow_job FINAL
    WHERE
        downstream_repo = {repo: String}
        AND event_type = 'nightly'
        AND if(
            match(pytorch_head_sha, '^[0-9a-fA-F]{40}$'),
            concat('sha:', pytorch_head_sha),
            concat('run:', if(run_id != '', run_id, pytorch_head_sha))
        ) IN (SELECT matrix_key FROM eligible_matrix_keys)
)

SELECT
    upstream_repo,
    pytorch_head_sha,
    workflow_name,
    job_name,
    check_run_id,
    run_id,
    run_attempt,
    status,
    conclusion,
    started_at,
    completed_at,
    duration_seconds,
    total_tests,
    passed_tests,
    failed_tests,
    skipped_tests,
    workflow_run_url,
    artifact_url,
    queue_time,
    execution_time,
    failed_tests_json
FROM
    deduped
WHERE
    rn = 1
ORDER BY
    started_at DESC
