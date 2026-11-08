"""Bancada fictícia do sincronizador; classificação no README da pasta pai."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PS = Path(os.environ.get("SystemRoot", "C:/Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"
GIT = shutil.which("git") or "C:/Program Files/Git/cmd/git.exe"


@unittest.skipUnless(PS.is_file(), "requer Windows PowerShell")
class SincronizarTests(unittest.TestCase):
    def setUp(self):
        (ROOT / "tmp").mkdir(exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(prefix="sincronizar-ficticio-", dir=ROOT / "tmp")
        self.addCleanup(self.tmp.cleanup)
        self.area = Path(self.tmp.name).resolve()
        self.site = self.area / "site"
        self.site.mkdir()
        self.apostilas = self.area / "Apostilas"
        self.mesa = self.apostilas / "00-MESA-DO-ALEX/02-EM-REVISAO"
        self.mesa.mkdir(parents=True)
        self.covers = self.apostilas / "01-OFICINA/graded-reader-studio/capas"
        self.covers.mkdir(parents=True)
        self.downloads = self.area / "Downloads"
        self.downloads.mkdir()
        self.catalogo = self.apostilas / "01-OFICINA/motor/catalogo_mesa.json"
        self.catalogo.parent.mkdir(parents=True)
        self.items = [{"aventura": s, "arquivo": "02-EM-REVISAO/" + s + ".html"} for s in ("alpha", "beta")]
        self.catalogo.write_text(json.dumps({"materiais": self.items}), encoding="utf-8")
        (self.site / "aventuras").mkdir()
        (self.site / "capas").mkdir()
        self.slugs = ["alpha", "beta", "dont-write", "dont-close", "dont-go-out"]
        for s in self.slugs:
            (self.site / "aventuras" / (s + ".html")).write_text("<html>ANTERIOR " + s + "</html>", encoding="utf-8")
            if s in ("alpha", "beta"):
                (self.mesa / (s + ".html")).write_text("<html>NOVO " + s + "</html>", encoding="utf-8")
        (self.covers / "capa.jpg").write_bytes(b"capa nova")
        (self.site / "capas/capa.jpg").write_bytes(b"capa anterior")
        (self.site / "index.html").write_text(''.join(f'<a href="aventuras/{s}.html">{s}</a>' for s in self.slugs) + '<img src="capas/capa.jpg">', encoding="utf-8")
        shutil.copy2(ROOT / "sincronizar.ps1", self.site)
        shutil.copy2(ROOT / ".gitignore", self.site)
        self.before = {p: p.read_bytes() for p in (self.site / "aventuras").glob("*")}
        self.before[self.site / "capas/capa.jpg"] = b"capa anterior"

    def executar(self, *args):
        env = os.environ.copy()
        # The runner may omit installed Git from PATH; the fixture supplies it
        # so the script's default `git` name is covered without a real remote.
        env["PATH"] = str(Path(GIT).parent) + os.pathsep + env.get("PATH", "")
        env.setdefault("PATHEXT", ".COM;.EXE;.BAT;.CMD")
        return subprocess.run([str(PS), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                               str(self.site / "sincronizar.ps1"), "-Apostilas", str(self.apostilas),
                               "-Downloads", str(self.downloads), *args], cwd=self.site,
                              env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20)

    def iguais(self):
        for p, dados in self.before.items():
            self.assertEqual(p.read_bytes(), dados)
        self.assertFalse((self.site / ".sincronizar-pendente").exists())

    def git(self, *args, check=True):
        return subprocess.run([GIT, "-C", str(self.site), *args], capture_output=True, text=True,
                              encoding="utf-8", errors="replace", check=check, timeout=20)

    def iniciar_git(self):
        if not Path(GIT).is_file():
            self.skipTest("git indisponível para a bancada")
        self.git("init", "-q")
        self.git("config", "user.name", "Teste ficticio")
        self.git("config", "user.email", "teste@example.invalid")
        self.git("add", "--", "index.html", "aventuras", "capas", "sincronizar.ps1", ".gitignore")
        self.git("commit", "-qm", "Fixture")

    def test_conferir_nao_grava_nem_precisa_git(self):
        result = self.executar("-GitExecutavel", str(self.area / "inexistente.exe"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Somente leitura", result.stdout)
        self.assertIn("Nao foram reconstruidas", result.stdout)
        self.iguais()

    def test_sincronizar_copia_catalogadas_e_preserva_extras(self):
        result = self.executar("-Sincronizar")
        self.assertEqual(result.returncode, 0, result.stderr)
        for s in ("alpha", "beta"):
            self.assertEqual((self.site / "aventuras" / (s + ".html")).read_bytes(), (self.mesa / (s + ".html")).read_bytes())
        for s in self.slugs[2:]:
            p = self.site / "aventuras" / (s + ".html")
            self.assertEqual(p.read_bytes(), self.before[p])
        self.assertFalse((self.site / ".sincronizar-pendente").exists())

    def test_download_explicito_html_completo_e_usado(self):
        (self.downloads / "dont-close.standalone.html").write_text("<html>exportado</html>", encoding="utf-8")
        result = self.executar("-Sincronizar")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.site / "aventuras/dont-close.html").read_text(), "<html>exportado</html>")

    def test_segundo_arquivo_aberto_restaura_o_primeiro(self):
        # Windows permits reading but denies Replace while Python holds this handle.
        with (self.site / "aventuras/beta.html").open("rb"):
            result = self.executar("-Sincronizar")
        self.assertNotEqual(result.returncode, 0)
        self.iguais()

    def test_fonte_ausente_interrompe_antes_de_copiar(self):
        (self.mesa / "beta.html").unlink()
        result = self.executar("-Sincronizar")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Fonte ausente", result.stderr)
        self.iguais()

    def test_extra_sem_download_nem_copia_bloqueia_lote(self):
        p = self.site / "aventuras/dont-close.html"
        p.unlink()
        self.before.pop(p)
        result = self.executar("-Sincronizar")
        self.assertNotEqual(result.returncode, 0)
        self.iguais()

    def test_download_invalido_bloqueia_sem_recorrer_silenciosamente_ao_site(self):
        (self.downloads / "dont-close.standalone.html").write_text("arquivo incompleto", encoding="utf-8")
        result = self.executar("-Sincronizar")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HTML completo", result.stderr)
        self.iguais()

    def test_catalogo_fora_da_mesa_bloqueia_lote(self):
        self.items[1]["arquivo"] = "../../fora.html"
        self.catalogo.write_text(json.dumps({"materiais": self.items}), encoding="utf-8")
        result = self.executar("-Sincronizar")
        self.assertNotEqual(result.returncode, 0)
        self.iguais()

    def test_indice_desatualizado_bloqueia_lote(self):
        p = self.site / "index.html"
        p.write_text(p.read_text().replace("beta.html", "inexistente.html"), encoding="utf-8")
        result = self.executar("-Sincronizar")
        self.assertNotEqual(result.returncode, 0)
        self.iguais()

    def test_trava_anterior_bloqueia_lote(self):
        lock = self.site / ".sincronizar-pendente"
        lock.mkdir()
        result = self.executar("-Sincronizar")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lock.is_dir())

    def test_falha_git_nao_anuncia_publicado(self):
        self.iniciar_git()
        # Only a local, nonexistent repository: no network or real remote.
        self.git("remote", "add", "origin", str(self.area / "remoto-inexistente.git"))
        self.git("config", "push.default", "current")
        # Exercise the default executable name as well (no function shadowing).
        result = self.executar("-Publicar")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Publicado:", result.stdout)
        self.assertIn("Git falhou", result.stderr)

    def test_publicar_recusa_mudanca_preexistente_sem_inclui_la(self):
        self.iniciar_git()
        (self.site / "anotacao.txt").write_text("mudança do usuário", encoding="utf-8")
        result = self.executar("-Publicar", "-GitExecutavel", GIT)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("mudancas locais", result.stderr)
        self.iguais()
        self.assertEqual(self.git("diff", "--cached", "--name-only").stdout, "")


if __name__ == "__main__":
    unittest.main()
