# Восстановление сценария съёмки

Здесь сохранены точные текстовые копии [скрипта](body_trait_text_shots.gd.txt) и [сцены](body_trait_text_shots.tscn.txt), использованных при повторной съёмке на `b6256b7`. Они не подключены к игре. Для воспроизведения нужен исходный проект Godot 4.6.3; итоговый английский кадр также требует перевода Ступеньки `RMB to recall within 6s.` в `data/i18n/en.po`. В другой версии данных результат может отличаться.

Работайте в отдельном checkout или worktree. Из корня проекта восстановите тестовые файлы, предварительно убедившись, что они не существуют: команда не перезапишет уже имеющиеся файлы.

```sh
if [ -e tests/body_trait_text_shots.gd ] || [ -e tests/body_trait_text_shots.tscn ]; then
  printf 'Тестовые файлы уже существуют; используйте отдельный worktree.\n' >&2
else
  cp docs/body_trait_gl_2026-10-28/scenario/body_trait_text_shots.gd.txt tests/body_trait_text_shots.gd
  cp docs/body_trait_gl_2026-10-28/scenario/body_trait_text_shots.tscn.txt tests/body_trait_text_shots.tscn
fi
```

После освобождения графического стенда выделите отдельные временные каталоги и выполните импорт. `ulimit` ограничивает каждый журнал размером менее 50 МБ; если первый импорт сообщает, что шрифт ещё не импортирован, сохраните его журнал и повторите импорт в другой файл.

```sh
thor_card_output=$(mktemp -d /tmp/thor-card-shots-XXXXXXXX)
thor_card_state=$(mktemp -d /tmp/thor-card-state-XXXXXXXX)
export XDG_DATA_HOME="$thor_card_state/data"
export XDG_CACHE_HOME="$thor_card_state/cache"
export XDG_CONFIG_HOME="$thor_card_state/config"
(ulimit -f 48000
 godot --headless --editor --path . --import
) > "$thor_card_output/import.log" 2>&1
printf 'Кадры и журналы: %s\n' "$thor_card_output"
```

После успешного импорта и при установленном `xvfb-run` запустите графическую сцену; для снимков нельзя применять `--headless`.

```sh
(ulimit -f 48000
 xvfb-run -a -s '-screen 0 1280x720x24' \
   godot --path . --fixed-fps 60 --audio-driver Dummy \
   --rendering-method gl_compatibility --resolution 1280x720 \
   res://tests/body_trait_text_shots.tscn -- "$thor_card_output"
) > "$thor_card_output/shot.log" 2>&1
```

В текущем окружении `xvfb-run` отсутствовал: фактический прогон использовал Xorg dummy. Его [конфигурация](../logs/xorg.conf) и [оригинальная оболочка запуска](../logs/run_gl.sh) сохранены для справки; оболочка содержит абсолютные пути исходного окружения и требует адаптации. `XDG_DATA_HOME` отделяет тестовые сохранения и настройки от данных игрока.

Сценарий принудительно предлагает Пике и Ступеньку и проверяет подписи, уровни и рамки, затем записывает четыре PNG и `manifest.json`. `ok` означает, что сценарий сохранил четыре кадра; `failed` содержит причину и текущий случай, `running` означает незавершённый прогон. Проверяйте также код выхода и полный `shot.log`: ошибки движка при запуске могут возникнуть до создания manifest. Даже при `ok` нужно проверить журнал и визуально осмотреть кадры; зафиксированные при исходном прогоне предупреждения и ошибки перечислены в [отчёте](../README.md).
