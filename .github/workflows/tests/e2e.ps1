function e2e ($branchToTest, $solutionName, $environmentUrl, $sourceBranch, $branchToCreate, $commitMessage) {
    $workflowFile = "export-unpack-commit-solution.yml"

    # run export-unpack-commit-solution.yml worklow 
    gh workflow run $workflowFile --ref $branchToTest `
    -f solution_name=$solutionName `
    -f environment_url=$environmentUrl `
    -f source_branch=$sourceBranch `
    -f branch_to_create=$branchToCreate `
    -f commit_message=$commitMessage `
    -f force_file_change=true 
    
     WaitForWorkflowToComplete $workflowFile $branchToTest 5

    # create a pr from branch with unpacked solution
    $title = "[wf-e2e-test] testing workflow changes in $branchToTest branch"
    gh pr create --base $sourceBranch --head $branchToCreate --title $title --body $title

    # wait for the pr workflow to run
    $workflowFile = "build-deploy-solution.yml"
    WaitForWorkflowToComplete $workflowFile $branchToCreate 30

    gh pr merge $branchToCreate --squash --delete-branch

    # wait for the uat workflow to run
    $workflowFile = "build-deploy-solution.yml"
    WaitForWorkflowToComplete $workflowFile $sourceBranch 30

    # deploy tagged solution    
    $dateFormat = Get-Date -Format "yyyyMMdd"
    $tagFilter = "*$dateFormat*"
    git fetch --all --tags
    $tags = git tag --list $tagFilter
    $latestTag = $tags[-1]
    $workflowFile = "deploy-tagged-solution-to-environment.yml"
    gh workflow run $workflowFile --ref $branchToTest -f tag=$latestTag -f environment=pr
    WaitForWorkflowToComplete $workflowFile $branchToTest 5

    # delete unmanaged solution from environment
    $workflowFile = "delete-unmanaged-solution-and-components-from-environment.yml"
    gh workflow run $workflowFile --ref $branchToTest -f solution_name=$solutionName -f environment_url=$environmentUrl
    WaitForWorkflowToComplete $workflowFile $branchToTest 5

    # import unmanaged solution from branch into dev environment
    $workflowFile = "import-unmanaged-solution.yml"
    gh workflow run $workflowFile --ref $branchToTest -f solution_name=$solutionName -f environment_url=$environmentUrl
    WaitForWorkflowToComplete $workflowFile $branchToTest 5

    # delete unmanaged solution from environment and import unmanaged solution from branch into dev environment
    $workflowFile = "delete-and-import-unmanaged-solution.yml"
    gh workflow run $workflowFile --ref $branchToTest -f solution_name=$solutionName -f environment_url=$environmentUrl
    WaitForWorkflowToComplete $workflowFile $branchToTest 5
}

function WaitForWorkflowToComplete ($workflowFile, $headBranch, $sleepSeconds) {
    Start-Sleep -s $sleepSeconds
    $workflowRunsJson = gh run list --workflow $workflowFile --json databaseId,headBranch,status
    $workflowRunsArray = ConvertFrom-Json $workflowRunsJson
    $testRun = $workflowRunsArray.Where({$_.headBranch -eq $headBranch -and $_.status -in "in_progress","queued"})[0]
    gh run watch $testRun.databaseId --interval 30
    $status = gh run view $testRun.databaseId --exit-status
    $hasExitCode1 = ($status -join '').Contains('exit code 1') 
    if ($hasExitCode1) {
        throw "$workflowFile run failed: see run logs for details"
    }
}