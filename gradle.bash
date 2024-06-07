#!/bin/bash

main () {
	local cmd="$@"
	{
		repo_name="$(basename "$PWD")"
		gradle_wrapper_properties_path="$HOME/$repo_name/gradle/wrapper/gradle-wrapper.properties"
#		gradle_version=$(gradle -v | sed -n '/^Gradle/p' | sed -r 's/Gradle //')
		gradle_version="8.5"
		gradle_bin_zip_name="gradle-$gradle_version-bin.zip"
		gradle_bin_zip_dir="$HOME/.gradle/wrapper/dists"


		echo "$(cat "$gradle_wrapper_properties_path" | sed "s!^distributionUrl=.*!distributionUrl=file\\\\:$gradle_bin_zip_dir/$gradle_bin_zip_name!")" > "$gradle_wrapper_properties_path"
	}
	{
		nvim -N -u NONE -n -c 'set nomore' -S <(echo -E ':%s/^plugins\(.*$\n^\)\{-}}//e | wq') "$HOME/$repo_name/app/build.gradle.kts" &> /dev/null
		build_script_path="$HOME/$repo_name/app/build.gradle.kts"
		echo "$(:
			cat "$build_script_path"
			cat << EOF | with_common_indent 0
				plugins {
					application
					id("org.jetbrains.kotlin.jvm") version "2.0.0"
				}
EOF
		)" > "$build_script_path"
	}
	{
		mkdir -p "$HOME/.gradle/init.d"
		echo "$OFFLINE_INIT_GRADLE_KTS" > "$HOME/.gradle/init.d/offline-init.gradle.kts"
	}
	{
		related_pid_list=($(ps -A | sed -nE "/(java|gradle)/p" | sed -E 's/^\s*([0-9]+).*/\1/g'))
		for pid in "${related_pid_list[@]}"; do
			kill -9 "$pid"
		done
		gradle --stop
	}
	{
		echo "Repo Name: $repo_name"
	}

	force_move_file_with_cmd f "$gradle_bin_zip_dir/$gradle_bin_zip_name" <(cat << EOF
		curl -LJO --create-dirs --output-dir "$gradle_bin_zip_dir" "https://services.gradle.org/distributions/$gradle_bin_zip_name" || {
			rm -rf "$gradle_bin_zip_dir/$gradle_bin_zip_name"
			rm -rf "$HOME/.gradle/repos"
		}
EOF
	)

	force_move_file_with_cmd d "$HOME/.gradle/repos" <(cat << EOF
		gradle_do reset || {
			rm -rf "$HOME/$repo_name/.gradle" 
			rm -rf "$HOME/$repo_name/.kotlin" 
			rm -rf "$HOME/$repo_name/build" 
			rm -rf "$HOME/$repo_name/app/build" 
			rm -rf "$HOME/.gradle/caches" 
			rm -rf "$HOME/.gradle/repos" 
		}
EOF
	)
	gradle_do "$cmd"
}

gradle_do () {
	cmd="$@"
	[[ "$cmd" =~ reset ]] && {
		local timer_max=10
		for i in $(seq 1 $timer_max); do
			echo "Resetting in $((timer_max - i + 1)) secs..."
			sleep 1
		done
		rm -rf "$HOME/$repo_name/.gradle" 
		rm -rf "$HOME/$repo_name/.kotlin" 
		rm -rf "$HOME/$repo_name/build" 
		rm -rf "$HOME/$repo_name/app/build" 
		rm -rf "$HOME/.gradle/caches" 
		rm -rf "$HOME/.gradle/repos" 
	}
	eval "$(:
		echo './gradlew \'
		[[ "$cmd" =~ version ]] && echo '-v \' || {
			([[ "$cmd" =~ build ]] || [[ "$cmd" =~ reset ]]) && echo 'clean build --refresh-dependencies \' || {
				[[ "$cmd" =~ run ]] && echo '--offline \'
			}
			[[ "$cmd" =~ run ]] && echo 'run \'
		}
		cat << "EOF"
			-Dorg.gradle.jvmargs="-Xmx2g" \
			--warning-mode all \
			--console=rich \
			--build-cache \
			-PmustSkipCacheToRepo=false \
			-PisVerboseCacheToRepo=false
EOF
	)"
}

force_move_file_with_cmd () {
	local file_type="$1"
	local dst_path="$2"
	local cmd="$3"
	local file_cmd
	eval_cmd () {
		echo "force_move_file_with_cmd: executing string: $cmd"
		eval "$cmd"
	}
	if (echo "$cmd" | sed -n "/\/proc\/self\/fd\//!q1"); then
		file_cmd="$(cat "$cmd")"
		eval_cmd () {
			echo "force_move_file_with_cmd: executing file: $cmd"
			echo -e "\n\n$(echo "$file_cmd" | with_common_indent 0)\n\n"
			eval "$file_cmd"
		}
	fi
	while true; do
		if [[ "$file_type" == "d" ]]; then
			if [ -d "$dst_path" ]; then
				return
			fi
		fi
		if [[ "$file_type" == "f" ]]; then
			if [ -f "$dst_path" ]; then
				return
			fi
		fi
		eval_cmd
		sleep 1
	done
}

with_common_indent () {
	local num_indents="$1"
	local str
	local str_tab_list
	str="$(cat)"
	str_tab_list=($(
		echo "$str" |
		sed -E 's/^(\t*).*/\1/g' |
		tr '\t' '-'
	))
	local least_num_indents=${#str_tab_list[1]}
	for str_tab in "${str_tab_list[@]}"; do
		least_num_indents=$(math_min ${#str_tab} $least_num_indents)
	done

	cur_common_indent=$(
		for i in $(seq 1 $least_num_indents); do
			echo -n '\t'
		done
	)

	new_common_indent=$(
		for i in $(seq 1 $num_indents); do
			echo -n '\t'
		done
	)

	echo "$str" |
		sed "s/^$cur_common_indent/$new_common_indent/g"
}

math_min () {
	local num1=$1
	local num2=$2
	if ((num1 < num2)); then
		echo $num1
	else
		echo $num2
	fi
}

OFFLINE_INIT_GRADLE_KTS=$(cat << "EOF"
fun main() {
	addLocalRepo()
	configureCacheToRepoTask()
}

fun configureCacheToRepoTask() {
	allprojects {
		buildscript {
			fun cacheToRepoInteractive() {
				val mustSkipCacheToRepo: String? by project
				val isVerboseCacheToRepo: String? by project
				val mustSkip = mustSkipCacheToRepo?.toBooleanStrictOrNull()
				val isVerbose = isVerboseCacheToRepo?.toBooleanStrictOrNull()
				cacheToRepo(mustSkip, isVerbose)
			}
			taskGraph.whenReady {
				val userSpecifiedTasks = startParameter.taskNames
				val allTasks = taskGraph.getAllTasks()
				if (userSpecifiedTasks.isNotEmpty()) {
					val lastTask = allTasks.last()
					lastTask.doLast {
						cacheToRepoInteractive()	
					}
				}
			}
		}
	}
}

fun addLocalRepo() {
	val reposDir = gradle.getGradleUserHomeDir().resolve("repos")
	val repoDir = reposDir.resolve("m2")
	repoDir.mkdirs()
	val repos = reposDir.listFiles().toList()
	beforeSettings {
		pluginManagement.repositories.addRepos(listOf(repoDir))
	}
	allprojects {
		repositories.addRepos(repos)
		buildscript.repositories.addRepos(repos)
	}
}

fun RepositoryHandler.addRepos(repos: List<File>?) {
	maven {
		repos?.forEach { repo ->
			setUrl(repo.toURI())
		}
	}
	gradlePluginPortal()
	mavenCentral()
	google()
}


fun cacheToRepo(mustSkip: Boolean? = null, isVerboseParam: Boolean? = null) {
	fun askUser(question: String) : Boolean {
		println("$question (yes/no)")
		return readLine()?.equals("yes", ignoreCase = true) ?: false
	}
	if (mustSkip ?: askUser("Skip cacheToRepo()?")) return

	var isVerbose = isVerboseParam ?: false 
	fun printVerbose(string: String) = when (isVerbose) {
		true -> println(string)
		false -> Unit
	}
	isVerbose = isVerboseParam ?: askUser("must be verbose?")

	val excludedFiletypes = listOf(".module")
	val includedFiletypes = listOf(".jar", ".pom")

	val cacheDir = file("${gradle.gradleUserHomeDir}/caches/modules-2/files-2.1")
	val customRepoDir = file("${gradle.gradleUserHomeDir}/repos/m2")

	println("\ncacheToRepo task is called.")
	println("cacheDir: $cacheDir")
	println("customRepoDir: $customRepoDir")

	cacheDir.walkTopDown().forEach { file ->
		if (!file.isFile) {
			printVerbose("File: ${file.name} - It's not a file.")
			return@forEach
		}
		printVerbose("File: ${file.name} - It's a file.")
		
		excludedFiletypes.forEach loop2@ { filetype ->
			if (!file.name.endsWith(filetype)) return@loop2
			printVerbose("File: ${file.name} - Excluded Filetype: ${filetype}")
			return@forEach
		}
		
		var isFiletypeIncluded = false
		for (filetype in includedFiletypes) {
			if (!file.name.endsWith(filetype)) continue
			isFiletypeIncluded = true
			break
		}
		if (!isFiletypeIncluded) {
			printVerbose("File: ${file.name} - Not in Included Filetypes: ${includedFiletypes.toString()}")
			if (!askUser("Do you want to copy this file?")) return@forEach
		}

		val relativePath = file.relativeTo(cacheDir).path
		val pathComponents = relativePath.split('/')
		val longPath = pathComponents[0].replace(".", "/")
		val name = pathComponents[1]
		val version = pathComponents[2]
		val ext = file.extension

		printVerbose("\tRelative path: $relativePath")
		printVerbose("\tlongPath: $longPath")
		printVerbose("\tname: $name")
		printVerbose("\tversion: $version")
		while (true) {	
			try {
				copy {
					from(file)
					rename {fileName ->
						val newName = when ("$name.$ext") {
							"kotlin-gradle-plugin.jar" -> "$name-$version.$ext"
							else -> fileName
						}
						if (newName != file.name) {
							printVerbose("File: ${file.name} - Renamed File To: $newName") 
						}
						newName
					}
					into("${customRepoDir.toPath()}/$longPath/$name/$version")
				}
				printVerbose("Successfully copied ${file.name}.")
				break
			} catch (e: Exception) {
				printVerbose("Failed to copy ${file.name}. Reason: ${e.message}")
				if (askUser("Skip copying this one?")) break
			}
		}
	}
}

main()
EOF
)

main "$@"
