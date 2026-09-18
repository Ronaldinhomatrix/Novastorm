@tool
extends Button

## Botão da toolbar: "Build + Rodar no Celular".
##
## Faz o ciclo completo de teste no aparelho, sem sair do editor:
##   1. exporta o projeto (export-debug, preset "Android") — o código que você
##      acabou de editar é empacotado no APK;
##   2. instala o APK no celular (adb install -r);
##   3. abre o jogo (adb shell am start).
##
## Cada passo roda em um processo separado e independente (OS.create_process),
## então o editor NUNCA congela enquanto o build/instalação acontece. A saída
## de cada comando é redirecionada para um log em user:// (fora do projeto),
## que é mostrado quando algum passo falha.
##
## Ctrl+clique: apenas abre no celular o jogo JÁ instalado (sem rebuild).

## Emitido quando o ciclo termina (útil para testes automatizados).
signal pipeline_finished(success: bool)

## Pacote do jogo no celular (Projeto > Exportar > Android > unique name).
const PACKAGE := "com.ronaldo.novastorm"

## Activity de launcher gerada pelo export Android do Godot.
const ACTIVITY := "com.godot.game.GodotAppLauncher"

const INTENT_ACTION := "android.intent.action.MAIN"
const INTENT_CATEGORY := "android.intent.category.LAUNCHER"

## Preset de export usado (nome exibido em Projeto > Exportar).
const EXPORT_PRESET := "Android"

## APK gerado pelo build.
const APK_PATH := "res://build/android/Novastorm.apk"

## Onde ficam os logs dos comandos (fora do projeto, para não sujar o repo).
const LOG_DIR := "user://mobile_launcher"

## Quantas linhas do log mostrar quando um passo falhar.
const LOG_TAIL_LINES := 15

## Espera entre o fim do export e o install, dando tempo para o sistema
## liberar o handle do APK recém-escrito.
const HANDLE_RELEASE_DELAY := 2.0

## O build Android reinicia o daemon do ADB e a redescoberta do celular sem fio
## leva alguns segundos. Nessas falhas de conexão o install é repetido; erros
## de verdade (assinatura, versão, espaço) falham na hora.
const INSTALL_RETRIES := 5
const INSTALL_RETRY_DELAY := 12.0

## O adb sem fio (TLS) larga e reencontra o celular sozinho, e o nome mDNS dele
## muda no meio do caminho. Quando o aparelho some na descoberta, ela é repetida
## antes de desistir.
const DEVICE_RETRIES := 3
const DEVICE_RETRY_DELAY := 8.0

## Trechos que indicam problema momentâneo de conexão, e não erro real.
const CONNECTION_ERRORS := [
	"no devices/emulators found",
	"device offline",
	# O adb escreve "device '<serial>' not found": o serial no meio da frase
	# impede casar com um texto pronto, então vale só o trecho final.
	"not found",
	"device unauthorized",
	"cannot connect",
	"connection reset",
	"closed",
	"more than one device",
]

## Variáveis de ambiente que apontam para o Android SDK.
const SDK_ENV_VARS := ["ANDROID_HOME", "ANDROID_SDK_ROOT"]

const LABEL_IDLE := "Build + Rodar no Celular"

enum Step { IDLE, CHECKING, EXPORTING, INSTALLING, LAUNCHING }

var _step: int = Step.IDLE
var _step_time: float = 0.0
var _label_time: float = 0.0
var _delay: float = 0.0
var _pid: int = -1
var _apk_before: String = ""
var _install_attempt: int = 0
var _adb: String = ""
var _serial: String = ""

## Só vale passar -s quando existe mais de um aparelho: com um único device o
## adb escolhe sozinho, e aí o install não depende do nome mDNS — que o adb sem
## fio troca por conta própria (o sufixo " (2)" aparece e some).
var _needs_serial: bool = false

## Ação a rodar assim que a verificação do celular passar. Serve para
## re-descobrir o aparelho no meio do pipeline (ex.: logo antes do install).
var _on_device_ready: Callable = Callable()

var _resolve_attempt: int = 0
var _quick_launch_only: bool = false
var _log_path: String = ""
var _pending: Callable = Callable()


func _ready() -> void:
	text = LABEL_IDLE
	tooltip_text = ("Compila o projeto (export debug Android), instala o APK no celular via ADB e abre o jogo.\n"
		+ "Ctrl+clique: só abre o jogo já instalado, sem rebuild.")
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(200, 0)
	set_process(false)
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


func _process(delta: float) -> void:
	_step_time += delta
	_label_time += delta

	if _pending.is_valid():
		_delay -= delta
		if _delay <= 0.0:
			var call := _pending
			_pending = Callable()
			call.call()
		return

	if _pid <= 0:
		return

	if _label_time >= 1.0:
		_label_time = 0.0
		text = "%s... %ds" % [_step_label(), int(_step_time)]

	if OS.is_process_running(_pid):
		return
	var pid := _pid
	_pid = -1
	_advance(OS.get_process_exit_code(pid))


## Disparado pelo botão (Ctrl+clique só abre o jogo já instalado).
func _on_pressed() -> void:
	if _step != Step.IDLE:
		return
	_adb = _find_adb()
	if _adb.is_empty():
		_fail("'adb' não encontrado. Defina ANDROID_HOME ou adicione o platform-tools ao PATH.")
		return

	if Input.is_key_pressed(KEY_CTRL):
		_quick_launch_only = true
	else:
		_quick_launch_only = false
	_install_attempt = 0
	_resolve_attempt = 0
	_resolve_device_then_continue()


## Chamado quando o comando do passo atual termina.
func _advance(exit_code: int) -> void:
	var elapsed := int(_step_time)
	_step_time = 0.0
	var tail := _log_tail()

	match _step:
		Step.CHECKING:
			if not _finish_device_resolve(exit_code):
				return
			if _on_device_ready.is_valid():
				var ready := _on_device_ready
				_on_device_ready = Callable()
				ready.call()
				return
			if _quick_launch_only:
				_step = Step.LAUNCHING
				_run(_adb, _with_serial(_launch_args()))
				return
			_start_export()
		Step.EXPORTING:
			var apk := ProjectSettings.globalize_path(APK_PATH)
			if exit_code != 0 or _fingerprint(apk) == _apk_before:
				_fail("exportação falhou (código %d).%s" % [exit_code, tail])
				return
			print("Novastorm Mobile Launcher: APK exportado em %ds (%s)." % [elapsed, APK_PATH])
			_step = Step.INSTALLING
			_defer(HANDLE_RELEASE_DELAY, _start_install)
		Step.INSTALLING:
			if exit_code != 0 or not _log_had_success():
				if _is_connection_error(tail) and _install_attempt < INSTALL_RETRIES:
					_install_attempt += 1
					print(("Novastorm Mobile Launcher: celular momentaneamente indisponível "
						+ "(tentativa %d/%d), repetindo em %ds. %s") % [
							_install_attempt, INSTALL_RETRIES, int(INSTALL_RETRY_DELAY), tail])
					_defer(INSTALL_RETRY_DELAY, _start_install)
					return
				_fail("adb install falhou (código %d).%s" % [exit_code, tail])
				return
			print("Novastorm Mobile Launcher: APK instalado no celular em %ds." % elapsed)
			_step = Step.LAUNCHING
			_run(_adb, _with_serial(_launch_args()))
		Step.LAUNCHING:
			if exit_code != 0:
				_fail("não foi possível abrir o jogo no celular (código %d).%s" % [exit_code, tail])
				return
			print("Novastorm Mobile Launcher: jogo aberto no celular (%s)." % PACKAGE)
			_finish(true)
		_:
			_finish(false)


## Inicia a exportação do APK em modo debug (o código editado vai junto).
func _start_export() -> void:
	var apk := ProjectSettings.globalize_path(APK_PATH)
	_apk_before = _fingerprint(apk)
	_step = Step.EXPORTING
	_run(OS.get_executable_path(), PackedStringArray([
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--export-debug", EXPORT_PRESET, apk,
	]))


## Instala o APK já exportado no celular (sobrescrevendo a versão anterior).
## O aparelho é redescoberto antes do install: entre a verificação inicial e
## aqui passaram os ~20s do export, e nesse intervalo o adb sem fio costuma
## renomear o celular — o serial lido no começo do pipeline deixa de existir.
func _start_install() -> void:
	_refresh_device_then(_install_now)


## Instala o APK no aparelho recém-descoberto.
func _install_now() -> void:
	_step = Step.INSTALLING
	_run(_adb, _with_serial(PackedStringArray(["install", "-r", ProjectSettings.globalize_path(APK_PATH)])))


## Agenda o próximo passo (sem travar o editor).
func _defer(seconds: float, call: Callable) -> void:
	_pending = call
	_delay = seconds
	_label_time = 1.0
	text = "%s... %ds" % [_step_label(), int(_step_time)]


## Roda um comando em um processo independente, com a saída redirecionada
## para um log. O editor não espera por ele: o fim é detectado no _process.
func _run(exe: String, args: PackedStringArray) -> void:
	_step_time = 0.0
	_label_time = 1.0
	_log_path = _new_log_path()
	# O cmd precisa de um caminho absoluto do sistema para o redirecionamento.
	var shell := _build_shell(exe, args, ProjectSettings.globalize_path(_log_path))
	_pid = OS.create_process(shell[0], shell[1])
	if _pid <= 0:
		_fail("não foi possível iniciar '%s'." % exe)
		return
	text = "%s... 0s" % _step_label()
	disabled = true
	set_process(true)


func _finish(success: bool) -> void:
	_pid = -1
	_step = Step.IDLE
	_step_time = 0.0
	_label_time = 0.0
	_pending = Callable()
	_on_device_ready = Callable()
	text = LABEL_IDLE
	disabled = false
	set_process(false)
	pipeline_finished.emit(success)


func _fail(message: String) -> void:
	push_error("Novastorm Mobile Launcher: " + message)
	_finish(false)


func _step_label() -> String:
	match _step:
		Step.CHECKING:
			return "Verificando celular"
		Step.EXPORTING:
			return "Exportando APK"
		Step.INSTALLING:
			return "Instalando no celular"
		Step.LAUNCHING:
			return "Abrindo no celular"
	return LABEL_IDLE


func _launch_args() -> PackedStringArray:
	return PackedStringArray([
		"shell", "am", "start", "-W",
		"-a", INTENT_ACTION,
		"-c", INTENT_CATEGORY,
		"-n", "%s/%s" % [PACKAGE, ACTIVITY],
	])


## Monta o comando passando pela shell, para poder redirecionar a saída.
func _build_shell(exe: String, args: PackedStringArray, log_path: String) -> Array:
	var parts := PackedStringArray([_quote(exe)])
	for arg in args:
		parts.append(_quote(arg))
	var line := " ".join(parts) + " > %s 2>&1" % _quote(log_path)
	if OS.get_name() == "Windows":
		return ["cmd.exe", PackedStringArray(["/c", line])]
	return ["/bin/sh", PackedStringArray(["-c", line])]


func _quote(value: String) -> String:
	if OS.get_name() == "Windows":
		return "\"" + value + "\""
	return "'" + value.replace("'", "'\\''") + "'"


func _new_log_path() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	# Nome único por execução: garante que o log lido pertence a ESTA tentativa.
	var suffix := "%s_%d" % [Time.get_time_string_from_system().replace(":", ""), Time.get_ticks_msec()]
	return LOG_DIR.path_join("step_%s_%s.log" % [_step_label().to_lower().replace(" ", "_"), suffix])


## A falha é só o celular/daemon temporariamente fora? (Vale repetir.)
func _is_connection_error(tail: String) -> bool:
	var lower := tail.to_lower()
	for needle in CONNECTION_ERRORS:
		if lower.contains(needle):
			return true
	return false


## O adb imprime "Success" quando a instalação dá certo.
func _log_had_success() -> bool:
	var text_log := _read_log()
	if text_log.strip_edges().is_empty():
		return true
	for line in text_log.split("\n"):
		if line.strip_edges() == "Success":
			return true
	return false


func _read_log() -> String:
	var path := ProjectSettings.globalize_path(_log_path)
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content := file.get_as_text()
	file.close()
	return content


## Últimas linhas do log, para diagnosticar a falha.
func _log_tail() -> String:
	var content := _read_log()
	if content.strip_edges().is_empty():
		return ""
	var lines := PackedStringArray()
	for line in content.split("\n"):
		var clean := line.strip_edges()
		if not clean.is_empty():
			lines.append(clean)
	if lines.is_empty():
		return ""
	var start := maxi(0, lines.size() - LOG_TAIL_LINES)
	return "\nLog do passo (%s):\n%s" % [_log_path, "\n".join(lines.slice(start))]


## Roda `adb devices` para descobrir o aparelho. A duplicata TLS que o adb sem
## fio cria (adb-XXXX (2)._adb-tls-connect._tcp) só é usada quando não existe a
## entrada normal do mesmo celular.
func _resolve_device_then_continue() -> void:
	_serial = ""
	_step = Step.CHECKING
	_run(_adb, PackedStringArray(["devices"]))


func _finish_device_resolve(exit_code: int) -> bool:
	if exit_code != 0:
		return _retry_device("celular nao conectado (adb devices falhou)")
	var serials: PackedStringArray = []
	for line in _read_log().split("\n"):
		var clean := line.strip_edges()
		if clean.is_empty() or clean.begins_with("List of devices"):
			continue
		var parts := clean.split("\t")
		if parts.size() < 2 or parts[1].strip_edges() != "device":
			continue
		var s := parts[0].strip_edges()
		serials.append(s)
	if serials.is_empty():
		return _retry_device("celular nao conectado (nenhum device com estado 'device')")
	# Preferencia: entrada normal; se so existir a fantasma "(2)", usa ela
	# (o adb sem fio as vezes expoe o aparelho SOMENTE pela entrada duplicada).
	var plain: PackedStringArray = []
	var dupes: PackedStringArray = []
	for s in serials:
		if s.contains(" (2)."):
			dupes.append(s)
		else:
			plain.append(s)
	var pool := plain if not plain.is_empty() else dupes
	_serial = pool[0]
	# Com um único aparelho não se passa -s: o adb escolhe sozinho e o install
	# fica imune ao nome mDNS, que muda sem avisar.
	_needs_serial = serials.size() > 1
	if pool.size() > 1 or not plain.is_empty() and not dupes.is_empty():
		print("Novastorm Mobile Launcher: %d celulares, usando %s." % [pool.size(), _serial])
	elif _serial.contains(" (2)."):
		print("Novastorm Mobile Launcher: usando entrada reserva %s." % _serial)
	return true


## Re-descobre o aparelho e só então roda `call` (o serial pode ter mudado).
func _refresh_device_then(call: Callable) -> void:
	_on_device_ready = call
	_resolve_device_then_continue()


## O celular sumiu só por instantes? Repete a descoberta; se insistir, aí falha.
## Devolve sempre false: quem chamou já encerra o passo atual (a nova tentativa
## fica agendada em _pending).
func _retry_device(reason: String) -> bool:
	_resolve_attempt += 1
	if _resolve_attempt <= DEVICE_RETRIES:
		print("Novastorm Mobile Launcher: %s (tentativa %d/%d), repetindo em %ds." % [
			reason, _resolve_attempt, DEVICE_RETRIES, int(DEVICE_RETRY_DELAY)])
		_defer(DEVICE_RETRY_DELAY, _resolve_device_then_continue)
		return false
	_fail("%s.%s" % [reason, _log_tail()])
	return false


## Prefixa -s <serial> para o comando falar com UM aparelho — mas só quando há
## mais de um conectado; com um único device o adb escolhe sozinho.
func _with_serial(args: PackedStringArray) -> PackedStringArray:
	if _serial.is_empty() or not _needs_serial:
		return args
	var out := PackedStringArray(["-s", _serial])
	out.append_array(args)
	return out

## Resolve o executável do adb: Android SDK (ANDROID_HOME / ANDROID_SDK_ROOT) ou PATH.
func _find_adb() -> String:
	var exe_name := "adb.exe" if OS.get_name() == "Windows" else "adb"
	for env_var in SDK_ENV_VARS:
		var sdk_dir := OS.get_environment(env_var)
		if sdk_dir.is_empty():
			continue
		var candidate := sdk_dir.path_join("platform-tools").path_join(exe_name)
		if FileAccess.file_exists(candidate):
			return candidate
	return "adb"


## Identifica o arquivo (tamanho + data) para saber se a exportação o reescreveu.
func _fingerprint(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var stamp := "%d:%d" % [FileAccess.get_modified_time(path), file.get_length()]
	file.close()
	return stamp