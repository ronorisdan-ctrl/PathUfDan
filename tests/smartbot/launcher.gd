extends Node
## Batch launcher for the smart bot. Needed when the project can only be started through
## a tool that runs a scene without command-line arguments (e.g. the Godot MCP
## run_project). Reads res://tests/smartbot/jobs.txt, starts every job as its own
## headless process with a fixed frame rate (deterministic, as fast as the CPU allows),
## runs up to `parallel=` jobs at once, captures each job's output to out/job_<n>.log and
## keeps out/launcher_status.txt up to date. Quits when all jobs are finished.
##
## jobs.txt format (one job per line, '#' comments):
##   parallel=4
##   --class=warrior --tier=1 --runs=5 --seed=1 --out=res://tests/smartbot/out/smoke.csv --trace=1
##   scene=res://tests/test_runner.tscn        (run another scene headless instead of the bot)
##   realtime scene=res://tests/bot.tscn      ('realtime': no --fixed-fps, normal frame timing)

const JOBS := "res://tests/smartbot/jobs.txt"
const OUT_DIR := "res://tests/smartbot/out"

var jobs := []
var parallel := 3
var status := {}
var mutex := Mutex.new()
var threads := []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# keep the Godot editor from importing result CSVs as translations
	var gi := OUT_DIR + "/.gdignore"
	if not FileAccess.file_exists(gi):
		var gf := FileAccess.open(gi, FileAccess.WRITE)
		if gf != null:
			gf.store_string("results - not game assets\n")
			gf.close()
	var txt := FileAccess.get_file_as_string(JOBS)
	for raw in txt.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("parallel="):
			parallel = maxi(1, int(line.get_slice("=", 1)))
			continue
		jobs.append(line)
	print("LAUNCHER %d jobs, parallel %d" % [jobs.size(), parallel])
	_write_status()
	# pre-flight: a script error would leave headless processes hanging forever, so check
	# that the bot boots before starting the batch
	if not _preflight():
		var f := FileAccess.open(OUT_DIR + "/launcher_status.txt", FileAccess.WRITE)
		f.store_string("PREFLIGHT FAILED - smartbot does not start (script error?). See out/preflight.log\n")
		f.close()
		get_tree().quit(1)
		return
	var next := 0
	var running := []
	while next < jobs.size() or not running.is_empty():
		while running.size() < parallel and next < jobs.size():
			var th := Thread.new()
			th.start(_run_job.bind(next, jobs[next]))
			running.append(th)
			threads.append(th)
			next += 1
		await get_tree().create_timer(1.0).timeout
		for th in running.duplicate():
			if not th.is_alive():
				th.wait_to_finish()
				running.erase(th)
		_write_status()
	_write_status(true)
	print("LAUNCHER DONE")
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()

func _preflight() -> bool:
	var ok_path := OUT_DIR + "/.check_ok"
	if FileAccess.file_exists(ok_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ok_path))
	var args := ["--headless", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"), "res://tests/smartbot/smartbot.tscn", "--", "--check=1", "--out=" + OUT_DIR + "/preflight.csv"]
	var pid := OS.create_process(OS.get_executable_path(), args)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		if FileAccess.file_exists(ok_path):
			return true
		if not OS.is_process_running(pid):
			break
		OS.delay_msec(250)
	if OS.is_process_running(pid):
		OS.kill(pid)
	if FileAccess.file_exists(ok_path):
		return true
	var out := []
	var pid2 := OS.create_process(OS.get_executable_path(), args)
	OS.delay_msec(15000)
	if OS.is_process_running(pid2):
		OS.kill(pid2)
	var f := FileAccess.open(OUT_DIR + "/preflight.log", FileAccess.WRITE)
	f.store_string("smartbot did not start within 60 s. Run it from a terminal to see the script error:\n" + " ".join(PackedStringArray(args)) + "\n")
	f.close()
	return false

func _run_job(i: int, line: String) -> void:
	var args := []
	var scene := "res://tests/smartbot/smartbot.tscn"
	var tps := 60
	var user := []
	var realtime := false
	for a in line.split(" ", false):
		if a == "realtime":
			realtime = true      # run without --fixed-fps (normal wall-clock frame timing)
		elif a.begins_with("scene="):
			scene = a.get_slice("=", 1)
		else:
			user.append(a)
			if a.begins_with("--tps="):
				tps = int(a.get_slice("=", 1))
	args = ["--headless", "--fixed-fps", str(tps), "--path", ProjectSettings.globalize_path("res://"), scene]
	if realtime:
		args = ["--headless", "--path", ProjectSettings.globalize_path("res://"), scene]
	if not user.is_empty():
		args.append("--")
		args.append_array(user)
	mutex.lock()
	status[i] = {"line": line, "state": "running", "start": Time.get_datetime_string_from_system()}
	mutex.unlock()
	var t0 := Time.get_ticks_msec()
	var output := []
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	var text := ""
	for o in output:
		text += str(o)
	var f := FileAccess.open(OUT_DIR + "/job_%d.log" % i, FileAccess.WRITE)
	if f != null:
		f.store_string("ARGS: %s\n\n%s" % [str(args), text])
		f.close()
	mutex.lock()
	status[i]["state"] = "done"
	status[i]["exit"] = code
	status[i]["secs"] = (Time.get_ticks_msec() - t0) / 1000.0
	var errs := 0
	for l in text.split("\n"):
		if l.contains("SCRIPT ERROR") or l.contains("Parse Error") or l.begins_with("ERROR"):
			errs += 1
	status[i]["errors"] = errs
	mutex.unlock()

func _write_status(final: bool = false) -> void:
	mutex.lock()
	var lines := ["%s  jobs=%d parallel=%d cpus=%d%s" % [Time.get_datetime_string_from_system(), jobs.size(), parallel, OS.get_processor_count(), "  ALL DONE" if final else ""]]
	for i in jobs.size():
		var s: Dictionary = status.get(i, {"state": "queued"})
		lines.append("job %d [%s] exit=%s secs=%s errors=%s :: %s" % [i, s.get("state", "?"), str(s.get("exit", "-")), str(s.get("secs", "-")), str(s.get("errors", "-")), jobs[i]])
	mutex.unlock()
	var f := FileAccess.open(OUT_DIR + "/launcher_status.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
