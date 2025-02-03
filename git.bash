#!/bin/bash

# shellcheck disable=SC2034,SC2317,SC2207,SC2046,SC2005,SC2002,SC2086,SC2115

main () (
	declare_strings "$@"
	declare_ssh_auth_eval
	add_ssh_key_to_ssh_agent
	exec_git_command "$@"
)

declare_strings () {
	REPO_NAME="project"
	BRANCH_NAME="main"
	GH_EMAIL="diamond2sword@gmail.com"
	GH_NAME="diamond2sword"
	DEFAULT_GIT_COMMAND_NAME="push"
	THIS_FILE_NAME="git.bash"
	PROJECT_NAME="project"
	SSH_DIR_NAME=".ssh"
	SSH_KEY_FILE_NAME="id_ed25519"
	ROOT_PATH="$HOME"
	REPO_PATH="$ROOT_PATH/$REPO_NAME"
	SSH_TRUE_DIR="$ROOT_PATH/$SSH_DIR_NAME"
	SSH_SYSTEM="ed25519"
	COMMIT_NAME="update project"
	SSH_KEY_PASSPHRASE="$(cat "$HOME/ssh-key-passphrase.txt")"
	REPO_URL="https://github.com/$GH_NAME/$REPO_NAME"
	SSH_REPO_URL="git@github.com:$GH_NAME/$REPO_NAME"
}

exec_git_command () {
	main () (
		local git_command="$1"; shift
		local args="$*"

		declare_git_commands
		reset_credentials
		if [[ "$git_command" == "git" ]]; then
			ssh_auth_eval "git $args"
			return
		fi	
		echo "cmd: '$git_command $args'"
		eval "$git_command" "$args"
	)

	is_var_set () {
		local git_command="$1"
		! [[ "$git_command" ]] && {
			return
		}
		return 0
	}

	main "$@"
}

declare_git_commands () {
	update_repos () {
		for_each_repo install_git_bash_to_repo
	}

	save_repos () (
		cmd() {
			repo_path="$HOME/$1"
			goto "$repo_path"
			echo -e "\nInfo: In $repo_path"
			./git.bash push
		}
		for_each_repo cmd
	)

	for_each_repo () {
		local cmd=$1
		local list
		list=($(find "$HOME"/**/git.bash | rev | cut -d '/' -f2 | rev))
		for repo_name in "${list[@]}"; do
			$cmd "$repo_name"
		done
	}

	install_git_bash_to_repo () {
		local repo_name="$1"
		local repo_path="$HOME/$repo_name"
		goto "$repo_path"
		# get branch name
		local branch_name
		branch_name="$(git rev-parse --abbrev-ref HEAD)"
		echo -en "Doing $repo_name/$branch_name\n"
		# copy files
		cp -rf "$REPO_PATH/git.bash" "$repo_path"
		rm -rf "$REPO_PATH/.ssh"
		# change git.bash content
		echo "$(cat "$repo_path/git.bash" | sed "s/REPO_NAME=\".*\"/REPO_NAME=\"$repo_name\"/" | sed "s/BRANCH_NAME=\".*\"/BRANCH_NAME=\"$branch_name\"/")" > "$repo_path/git.bash"
	}

	login () {
		local passphrase="$SSH_KEY_PASSPHRASE"
		local system="$SSH_SYSTEM"
		local ssh_key_title="termux"

		gh auth logout

		gh auth login -p ssh --skip-ssh-key -w -s read:gpg_key,admin:public_key,admin:ssh_signing_key,delete_repo || exit 1

		rm -rf $HOME/.ssh

		expect << EOF
			spawn ssh-keygen -t "$system" -C "$GH_EMAIL"
			expect {
				-re {Enter file in which to save the key} {
					send "\r"
					exp_continue
				}
				-re {empty for no passphrase} {
					send "$passphrase\r"
					exp_continue
				}
				-re {Enter same passphrase again} {
					send "$passphrase\r"
					exp_continue
				}
				eof
			}
EOF

		local key_path="$HOME/.ssh/id_$system"
		chmod 600 "$key_path"
		eval "$(ssh-agent -s)"

		expect << EOF
			spawn ssh-add "$key_path"
			expect {
				-re {Enter passphrase for} {
					send "$passphrase\r"
					exp_continue
				}
				eof
			}
EOF

		cat "$key_path.pub"

		gh ssh-key add "$key_path.pub" -t "termux"

		delete_ssh_keys_except_last
	}

	delete_ssh_keys_except_last()
	{
		local list
		list=$(gh ssh-key list)
		echo "$list" |
		grep -v "$(echo "$list" | awk '{print $4}' | sort | tail -n 1)" |
		awk '{print $5}' | xargs -I {} gh ssh-key delete {} --yes
	}

	fix_ahead_commits () {
		mkdir -p "$REPO_PATH.bak"
		cp -r "$REPO_PATH/"* "$REPO_PATH.bak"
		git checkout "$BRANCH_NAME"
		git pull -s recursive -X theirs
		git reset --hard origin/$BRANCH_NAME
	}

	rebase () {
		goto "$REPO_PATH"
		ssh_auth_eval "git pull origin $BRANCH_NAME --rebase --autostash"
		ssh_auth_eval "git rebase --continue"
	}

	clone () {
		local repo_name="$1"
		goto "$HOME"
		gh repo clone "$repo_name"
	}

	reset_credentials () {
		goto "$REPO_PATH"
		git config --global --unset credential.helper
		git config --system --unset credential.helper
		git config --global user.name "$GH_NAME"
		git config --global user.email "$GH_EMAIL"
	}

	push () {
		[[ $1 ]] && COMMIT_NAME="$1"
		goto "$REPO_PATH"
		git add .
		git commit -m "$COMMIT_NAME"
		git remote set-url origin "$SSH_REPO_URL"
		ssh_auth_eval "git push -u origin $BRANCH_NAME"
	}

	goto () {
		cd "$1" || {
			echo "Info: Cannot CD to $1"
			exit 1
		}
		echo "Info: In $1"
	}

	reclone () {
		local repo_name="$1"
		rm -rf "$HOME/$repo_name"
		clone "$repo_name"
	}
}

add_ssh_key_to_ssh_agent () {
	chmod 600 "$SSH_TRUE_DIR/$SSH_KEY_FILE_NAME"
	eval "$(ssh-agent -s)"
	ssh_auth_eval ssh-add "$SSH_TRUE_DIR/$SSH_KEY_FILE_NAME"
}


declare_ssh_auth_eval () {
eval "$(cat <<- "EOF"
	ssh_auth_eval () {
		command="$@"
		ssh_key_passphrase="$SSH_KEY_PASSPHRASE"
		expect << EOF2
			spawn $command
			expect {
				-re {Enter passphrase for} {
					send "$ssh_key_passphrase\r"
					exp_continue
				}
				-re {Are you sure you want to continue connecting} {
					send "yes\r"
					exp_continue
				}
				eof
			}
		EOF2
	}
EOF
)"
}

main "$@"
