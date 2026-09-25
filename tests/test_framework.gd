extends RefCounted

## Lightweight automated testing framework for Pterodon GDScript test suites.

var current_test_name: String = ""
var current_test_failed: bool = false
var current_tier_name: String = ""

# Master cumulative counters
var total_assertions: int = 0
var passed_assertions: int = 0
var failed_assertions: int = 0

var total_tests: int = 0
var passed_tests: int = 0
var failed_tests: int = 0

# Per-tier counters
var tier_total_tests: int = 0
var tier_passed_tests: int = 0
var tier_failed_tests: int = 0
var tier_total_assertions: int = 0
var tier_passed_assertions: int = 0
var tier_failed_assertions: int = 0

var failure_log: Array[Dictionary] = []


func begin_tier(tier_name: String) -> void:
	current_tier_name = tier_name
	tier_total_tests = 0
	tier_passed_tests = 0
	tier_failed_tests = 0
	tier_total_assertions = 0
	tier_passed_assertions = 0
	tier_failed_assertions = 0
	print("\n>>> STARTING: ", tier_name)


func end_tier() -> void:
	print("------------------------------------------------------------------")
	print("SUMMARY FOR: ", current_tier_name)
	print("  Tests:      ", tier_passed_tests, "/", tier_total_tests, " passed", (" [FAILED]" if tier_failed_tests > 0 else " [ALL PASSED]"))
	print("  Assertions: ", tier_passed_assertions, "/", tier_total_assertions, " passed", (" (" + str(tier_failed_assertions) + " failed)" if tier_failed_assertions > 0 else ""))
	print("------------------------------------------------------------------")


func start_test(test_name: String) -> void:
	current_test_name = test_name
	current_test_failed = false
	total_tests += 1
	tier_total_tests += 1


func end_test() -> void:
	if current_test_failed:
		failed_tests += 1
		tier_failed_tests += 1
		print("  ❌ [FAIL] ", current_test_name)
	else:
		passed_tests += 1
		tier_passed_tests += 1
		print("  ✅ [PASS] ", current_test_name)
	current_test_name = ""


func assert_true(condition: bool, message: String = "") -> bool:
	total_assertions += 1
	tier_total_assertions += 1
	if condition:
		passed_assertions += 1
		tier_passed_assertions += 1
		return true
	_record_failure("Expected TRUE, but got FALSE. " + message)
	return false


func assert_false(condition: bool, message: String = "") -> bool:
	total_assertions += 1
	tier_total_assertions += 1
	if not condition:
		passed_assertions += 1
		tier_passed_assertions += 1
		return true
	_record_failure("Expected FALSE, but got TRUE. " + message)
	return false


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> bool:
	total_assertions += 1
	tier_total_assertions += 1
	if actual == expected:
		passed_assertions += 1
		tier_passed_assertions += 1
		return true
	_record_failure("Expected [" + str(expected) + "], but got [" + str(actual) + "]. " + message)
	return false


func assert_ne(actual: Variant, expected: Variant, message: String = "") -> bool:
	total_assertions += 1
	tier_total_assertions += 1
	if actual != expected:
		passed_assertions += 1
		tier_passed_assertions += 1
		return true
	_record_failure("Expected value different from [" + str(expected) + "]. " + message)
	return false


func assert_null(value: Variant, message: String = "") -> bool:
	total_assertions += 1
	tier_total_assertions += 1
	if value == null:
		passed_assertions += 1
		tier_passed_assertions += 1
		return true
	_record_failure("Expected NULL, but got [" + str(value) + "]. " + message)
	return false


func assert_not_null(value: Variant, message: String = "") -> bool:
	total_assertions += 1
	tier_total_assertions += 1
	if value != null:
		passed_assertions += 1
		tier_passed_assertions += 1
		return true
	_record_failure("Expected NOT NULL, but got NULL. " + message)
	return false


func assert_almost_eq(actual: float, expected: float, tolerance: float = 0.001, message: String = "") -> bool:
	total_assertions += 1
	tier_total_assertions += 1
	if absf(actual - expected) <= tolerance:
		passed_assertions += 1
		tier_passed_assertions += 1
		return true
	_record_failure("Expected [" + str(expected) + "] (+/-" + str(tolerance) + "), but got [" + str(actual) + "]. " + message)
	return false


func assert_vector3_almost_eq(actual: Vector3, expected: Vector3, tolerance: float = 0.001, message: String = "") -> bool:
	total_assertions += 1
	tier_total_assertions += 1
	if actual.distance_to(expected) <= tolerance:
		passed_assertions += 1
		tier_passed_assertions += 1
		return true
	_record_failure("Expected Vector3 " + str(expected) + " (+/-" + str(tolerance) + "), but got " + str(actual) + ". " + message)
	return false


func _record_failure(msg: String) -> void:
	failed_assertions += 1
	tier_failed_assertions += 1
	current_test_failed = true
	var entry := {
		"tier": current_tier_name,
		"test": current_test_name,
		"message": msg
	}
	failure_log.append(entry)
	print("    ASSERTION FAILED: ", msg)


func has_failed() -> bool:
	return failed_tests > 0 or failed_assertions > 0


func print_master_summary() -> void:
	print("\n==================================================================")
	print("                    FINAL TEST REPORT                             ")
	print("==================================================================")
	print("Total Test Cases: ", total_tests)
	print("  Passed:         ", passed_tests)
	print("  Failed:         ", failed_tests)
	print("Total Assertions: ", total_assertions)
	print("  Passed:         ", passed_assertions)
	print("  Failed:         ", failed_assertions)

	if failure_log.size() > 0:
		print("\nFailure Details Summary:")
		for fail in failure_log:
			print("  * [", fail["tier"], " -> ", fail["test"], "]: ", fail["message"])

	if has_failed():
		print("\n❌ SUITE RESULT: FAILED (Some tests or assertions failed)")
	else:
		print("\n✅ SUITE RESULT: PASSED (All tests and assertions passed)")
	print("==================================================================")
