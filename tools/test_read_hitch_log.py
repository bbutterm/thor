#!/usr/bin/env python3
import hashlib
from pathlib import Path
import tempfile
import unittest
from tools import read_hitch_log as reader


def complete(method='forward_plus', result=0, rooms='10 из 10', slams=42, noise=None,
             pso='нет', before='', after='', pso_details=None):
    output = [f'=== HITCH TEST (порог +50 мс к медиане, {method}) ===', 'OpenGL API synthetic']
    if before:
        output += ['context before', before, 'context after']
    output += ['Кадров: 100, медиана 10.0 мс; худший всплеск по событию вне загрузки залов: +0.0 мс',
               '      кадр 9  80.0 мс (медиана 10.0)  [pso_draw+99]  (до: )']
    if result:
        output.append('  >>> кадр 10  80.0 мс (медиана 10.0)  [enemy_hit]  (до: fx_sparks)')
    if noise:
        output.append('    ~ кадр 11  85.0 мс (медиана 10.0)  []  (до: )')
    if noise is not None:
        output.append(f'Всплесков без событий > +50 мс: {noise} (не считаются)')
    output += [f'Компиляции пайплайнов вне загрузки залов: {pso}']
    output.extend(pso_details or [])
    output += [
               f'Пройдено залов: {rooms}', f'Удары-приземления с реальным приземлением: {slams}',
               f'=== ИТОГ HITCH: {result} фризов > +50 мс вне загрузки ===']
    if after:
        output += ['cleanup before', after, 'cleanup after']
    return '\n'.join(output) + '\n'


class HitchLogReaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def write(self, log, method='forward_plus', exit_code=0):
        (self.path / 'godot.log').write_text(log, encoding='utf-8')
        (self.path / 'metadata.txt').write_text(f'method={method}\nthreshold_ms=50\nexit_code={exit_code}\n', encoding='utf-8')

    def test_known_gl_log_read_only(self):
        path = Path('/workspace/thor-artifacts/hitch-n11/gl-final-6a5baec')
        if not (path/'godot.log').exists():
            self.skipTest('historical GL log unavailable')
        digest = hashlib.sha256((path/'godot.log').read_bytes()).hexdigest()
        r = reader.summarize(path)
        self.assertEqual((r['rooms']['completed'], r['rooms']['total'], r['actual_landings']), (10, 10, 42))
        self.assertEqual((r['event_hitches'], r['unmarked_spikes']), (29, 34))
        self.assertEqual((r['errors']['execution_count'], r['errors']['after_result_count']), (54, 2))
        self.assertEqual(r['pso_draw_outside_loading']['state'], 'unavailable_for_renderer')
        self.assertIsNone(r['pso_draw_outside_loading']['draw_compilations'])
        self.assertFalse(r['launcher_and_test_pass'])
        self.assertFalse(r['clean_shutdown'])
        self.assertEqual(r['resource_warnings_after_result'], 1)
        self.assertEqual(digest, hashlib.sha256((path/'godot.log').read_bytes()).hexdigest())

    def test_mixed_forward_and_error_positions(self):
        self.write(complete(result=1, noise=4, pso='{ "pso_draw": 3, "pso_mesh": 2 }',
                            before='prefix ERROR: render failed\n   at: main\n   backtrace:\n     frame 1\n     frame 2',
                            after='ERROR: Texture leaked',
                            pso_details=['  кадр 10  80.0 мс  pso_draw+3  [pso_draw+3]  (до: enemy_hit)']), exit_code=1)
        r = reader.summarize(self.path)
        self.assertEqual((r['event_hitches'], r['unmarked_spikes']), (1, 4))
        self.assertEqual(r['pso_draw_outside_loading']['draw_compilations'], 3)
        self.assertTrue(r['pso_draw_requires_review'])
        self.assertEqual((r['errors']['execution_count'], r['errors']['after_result_count']), (1, 1))
        self.assertIn('context before', r['errors']['entries'][0]['context'])
        self.assertIn('     frame 2', r['errors']['entries'][0]['context'])
        self.assertIn('cleanup after', r['errors']['entries'][1]['context'])
        event_row = next(row for row in r['spike_rows'] if row['kind'] == 'event')
        self.assertEqual(event_row['previous'], 'fx_sparks')
        self.assertEqual(r['spike_rows_above_half_threshold']['loading'], 1)
        self.assertEqual(len(r['pso_draw_outside_loading']['detail_lines']), 1)
        self.assertIn('pso_draw+3', r['pso_draw_outside_loading']['detail_lines'][0]['text'])

    def test_gl_no_pso_counter_and_noise_absent(self):
        self.write(complete(method='gl_compatibility'), method='gl_compatibility')
        r = reader.summarize(self.path)
        self.assertEqual(r['unmarked_spikes'], 0)
        self.assertEqual(r['pso_draw_outside_loading']['state'], 'unavailable_for_renderer')
        self.assertIsNone(r['pso_draw_requires_review'])
        self.assertTrue(r['launcher_and_test_pass'])
        self.assertTrue(r['clean_shutdown'])

    def test_draw_requires_review_even_when_launcher_and_test_pass(self):
        self.write(complete(pso='{ "pso_draw": 3 }'))
        r = reader.summarize(self.path)
        self.assertTrue(r['launcher_and_test_pass'])
        self.assertTrue(r['pso_draw_requires_review'])
        self.assertEqual(r['pso_draw_outside_loading']['draw_compilations'], 3)

    def test_resource_warning_is_separate_from_test_and_clean_shutdown(self):
        self.write(complete(after='WARNING: ObjectDB instances leaked at exit'))
        r = reader.summarize(self.path)
        self.assertTrue(r['launcher_and_test_pass'])
        self.assertFalse(r['clean_shutdown'])
        self.assertEqual(r['resource_warnings_after_result'], 1)

    def test_partial_error_phase_is_unknown(self):
        self.write('=== HITCH TEST (порог +50 мс к медиане, forward_plus) ===\nERROR: incomplete\n')
        r = reader.summarize(self.path)
        self.assertFalse(r['complete_summary'])
        self.assertIsNone(r['event_hitches'])
        self.assertIsNone(r['unmarked_spikes'])
        self.assertEqual(r['errors']['undetermined_count'], 1)
        self.assertFalse(r['launcher_and_test_pass'])

    def test_forward_no_draw_but_other_compiles(self):
        self.write(complete(pso='{ "pso_mesh": 8 }'))
        r = reader.summarize(self.path)
        self.assertEqual(r['pso_draw_outside_loading']['draw_compilations'], 0)
        self.assertFalse(r['pso_draw_requires_review'])

    def test_unparsed_pso_is_unknown(self):
        self.write(complete(pso='driver unavailable'))
        r = reader.summarize(self.path)
        self.assertEqual(r['pso_draw_outside_loading']['state'], 'unparsed_report')
        self.assertIsNone(r['pso_draw_requires_review'])

    def test_invalid_draw_value_cannot_be_treated_as_zero(self):
        self.write(complete(pso='{ "pso_draw": "3" }'))
        r = reader.summarize(self.path)
        self.assertEqual(r['pso_draw_outside_loading']['state'], 'unparsed_report')
        self.assertIsNone(r['pso_draw_outside_loading']['draw_compilations'])

    def test_mixed_parse_script_and_hitch_errors_are_counted(self):
        self.write(complete(before='prefix ERROR: rendering\nSCRIPT ERROR: bad call\nParse Error: bad script\nHITCH FAIL: no hit',
                            after='prefix ERROR: cleanup'))
        r = reader.summarize(self.path)
        self.assertEqual((r['errors']['execution_count'], r['errors']['after_result_count']), (4, 1))
        self.assertFalse(r['launcher_and_test_pass'])

    def test_duplicate_result_does_not_guess_error_phase(self):
        self.write(complete(before='ERROR: failure') + '=== ИТОГ HITCH: 0 фризов > +50 мс вне загрузки ===\n')
        r = reader.summarize(self.path)
        self.assertIn('multiple_result_lines:2', r['integrity_issues'])
        self.assertEqual(r['errors']['undetermined_count'], 1)
        self.assertFalse(r['complete_summary'])

    def test_bad_room_count_and_no_landings(self):
        self.write(complete(rooms='9 из 9', slams=0))
        r = reader.summarize(self.path)
        self.assertFalse(r['launcher_and_test_pass'])
        self.assertEqual(r['actual_landings'], 0)

    def test_requested_method_mismatch(self):
        self.write(complete(method='gl_compatibility'), method='forward_plus')
        r = reader.summarize(self.path)
        self.assertFalse(r['method_matches_request'])
        self.assertFalse(r['launcher_and_test_pass'])

    def test_cap_hint_and_short_does_not_modify(self):
        self.write(complete(before='SCRIPT ERROR: bad', after='WARNING: ObjectDB instances leaked'))
        before = (self.path/'godot.log').read_bytes()
        old = reader.CAP_BYTES
        self.addCleanup(setattr, reader, 'CAP_BYTES', old)
        reader.CAP_BYTES = 3
        r = reader.summarize(self.path, short=True)
        self.assertIn('log_at_or_above_50MB_cap_may_be_truncated', r['integrity_issues'])
        self.assertEqual(r['errors']['entries'], [])
        self.assertEqual(r['errors']['execution_count'], 1)
        self.assertEqual(len(r['warnings_after_result']), 1)
        self.assertIsNone(r['clean_shutdown'])
        self.assertEqual(before, (self.path/'godot.log').read_bytes())

if __name__ == '__main__':
    unittest.main(verbosity=2)
