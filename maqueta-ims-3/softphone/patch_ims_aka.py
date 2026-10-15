from pathlib import Path
import shutil


def replace_once(path: str, original: str, replacement: str) -> None:
    file_path = Path(path)
    contents = file_path.read_text()
    if contents.count(original) != 1:
        raise RuntimeError(f"Expected one patch location in {path}")
    file_path.write_text(contents.replace(original, replacement, 1))


replace_once(
    "third_party/milenage/milenage.c",
    """  RijndaelEncrypt( op, op_c );
  for (i=0; i<16; i++)
    op_c[i] ^= op[i];
""",
    """  /* The HSS provisions OPc, so the AKA input is already OPc. */
  for (i=0; i<16; i++)
    op_c[i] = op[i];
""",
)

for source, target in (
    ("third_party/milenage/milenage.c", "pjsip/src/pjsip/ims_milenage.c"),
    ("third_party/milenage/milenage.h", "pjsip/src/pjsip/milenage.h"),
    ("third_party/milenage/rijndael.c", "pjsip/src/pjsip/ims_rijndael.c"),
    ("third_party/milenage/rijndael.h", "pjsip/src/pjsip/rijndael.h"),
):
    shutil.copyfile(source, target)

replace_once(
    "pjsip/build/Makefile",
    "sip_auth_server.o \\\n",
    "sip_auth_server.o ims_milenage.o ims_rijndael.o \\\n",
)
replace_once(
    "pjsip-apps/src/pjsua/pjsua_app.c",
    "static pjsip_module mod_default_handler =",
    '#include "ims_ext.c"\n\nstatic pjsip_module mod_default_handler =',
)
replace_once(
    "pjsip-apps/src/pjsua/pjsua_app.c",
    """                                         &mod_default_handler);
    if (status != PJ_SUCCESS)
        return status;
""",
    """                                         &mod_default_handler);
    if (status != PJ_SUCCESS)
        return status;

    status = ims_ext_init(&app_config);
    if (status != PJ_SUCCESS)
        return status;
""",
)
