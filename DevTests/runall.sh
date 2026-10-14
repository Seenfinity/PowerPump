#!/bin/zsh
# Runs every test suite against the app's current sources.
SRC="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC/../SpartanBody"
T=${TMPDIR:-/tmp}/powerpump-tests; mkdir -p $T/coachtest/matrix $T/coachtest/form $T/live $T/topics
U=${SIM_UDID:-booted}
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SC=(xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator -sdk "$SDK" -O)
# A test that no longer compiles must not run its old binary.
rm -f $T/coachtest/coachtest $T/coachtest/matrixtest $T/coachtest/formtest $T/live/t $T/topics/t $T/chips/t $T/ex/t
FILES=(Core/Models/FitnessPlanModels.swift Core/Services/CoachAnalyzer.swift Core/Services/WeeklyPlanner.swift Core/Services/DietPlanner.swift Core/Services/LocalCoachService.swift Core/Services/ProgressionEngine.swift Core/Models/WorkoutModels.swift Core/Models/ProgressModels.swift Core/Models/Exercise.swift Core/Services/ExerciseDatabase.swift Core/Models/RecipeModels.swift Core/Services/RecipeDatabase.swift Core/Models/FoodModels.swift Core/Services/FoodDatabase.swift Core/Models/SportActivity.swift Core/Models/UserProfile.swift Core/Services/LanguageManager.swift Core/Services/ProgramStrings.swift Core/Services/WeeklyReviewEngine.swift Core/Services/ExerciseStrings.swift)
"${SC[@]}" -o $T/coachtest/coachtest "${FILES[@]}" "$SRC/coach/main.swift" 2>&1 | grep error: | head -3
"${SC[@]}" -o $T/coachtest/matrixtest "${FILES[@]}" "$SRC/matrix/main.swift" 2>&1 | grep error: | head -3
"${SC[@]}" -o $T/live/t Core/Services/VideoFormEngine.swift Core/Services/LiveFormTracker.swift "$SRC/live/main.swift" 2>&1 | grep error: | head -3
"${SC[@]}" -o $T/coachtest/formtest Core/Services/VideoFormEngine.swift "$SRC/form/main.swift" 2>&1 | grep error: | head -3
swiftc -O -o $T/topics/t Core/Services/CoachTopics.swift "$SRC/chat/main.swift" 2>&1 | grep error: | head -3
mkdir -p $T/ex && python3 "$SRC/chat/exercises.py" . > $T/ex/main.swift && swiftc -O -o $T/ex/t Core/Services/CoachTopics.swift $T/ex/main.swift 2>&1 | grep error: | head -3
mkdir -p $T/chips && python3 "$SRC/chat/chips.py" Localizable.xcstrings > $T/chips/main.swift && swiftc -O -o $T/chips/t Core/Services/CoachTopics.swift $T/chips/main.swift 2>&1 | grep error: | head -3
echo "=== 1. Coach (escenarios) ==="; OUT=$(xcrun simctl spawn $U $T/coachtest/coachtest 2>&1); echo "$OUT" | grep -E "FAIL|signal"; echo "PASS: $(echo "$OUT" | grep -c PASS)  FAIL: $(echo "$OUT" | grep -c FAIL)"
echo "=== 2. Matriz de planes ==="; xcrun simctl spawn $U $T/coachtest/matrixtest 2>&1 | grep -E "Planes|FALLA|TODO|signal"
echo "=== 3. Análisis de vídeo ==="; OUT=$(xcrun simctl spawn $U $T/coachtest/formtest 2>&1); echo "$OUT" | grep -E "FAIL|TODO|signal"
echo "=== 4. Temas del chat ==="; $T/topics/t | grep -E "FALLO|TODO"
echo "=== 4b. Botones de sugerencia ==="; $T/chips/t | grep -E "FALLO|TODO"
echo "=== 4c. Preguntar a Spartan por cada ejercicio ==="; $T/ex/t | grep -E "FALLO|TODO"
echo "=== 5. Corrección en vivo ==="; xcrun simctl spawn $U $T/live/t 2>&1 | grep -E "FAIL|TODO|signal"
