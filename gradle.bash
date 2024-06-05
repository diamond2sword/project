#!/bin/bash

REPO_NAME="project"

main () {
	local cmd="$1"
	{
		gradle_wrapper_properties_path="$HOME/$REPO_NAME/gradle/wrapper/gradle-wrapper.properties"
		echo "$(
			cat "$gradle_wrapper_properties_path" |
			sed "s!^distributionUrl=.*!distributionUrl=file\\:$HOME/.gradle/wrapper/dists/gradle-8.5-bin.zip!"
		)" > "$gradle_wrapper_properties_path"
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
	"gradle_$cmd"
}

gradle_build () {
	./gradlew clean build \
		--refresh-dependencies \
		--build-cache \
		-Dorg.gradle.jvmargs="-Xmx2g" \
		--console=rich \
		--warning-mode all \
		-PmustSkipCacheToRepo=false \
		-PisVerboseCacheToRepo=false
}

gradle_run () {
	./gradlew run \
		-Dorg.gradle.jvmargs="-Xmx2g" \
		--console=rich \
		--warning-mode all \
		-PmustSkipCacheToRepo=false \
		-PisVerboseCacheToRepo=false
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
					into("${customRepoDir.toPath()}$longPath/$name/$version")
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
