extends Panel

func _ready():
	%GitBranch.text = YourBuil.git_branch
	%GitCommitCount.text = str(YourBuil.git_commit_count)
	%GitCommitHash.text = YourBuil.git_commit_hash
	%GitTag.text = YourBuil.git_tag
	%Date.text = YourBuil.get_date_string()
	%Time.text = YourBuil.get_time_string()
