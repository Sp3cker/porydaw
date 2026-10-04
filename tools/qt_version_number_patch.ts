// Swift 6.4's Windows Clang importer cannot convert Qt 6.11's Qt::strong_ordering
// to std::strong_ordering in QVersionNumber's iterator operator<=>.
// Usage: deno run --allow-read --allow-write tools/qt_version_number_patch.ts <qt-prefix>
import { join } from "node:path";

const oldReturn = "return compareThreeWay(lhs, rhs);";
const fixedReturn = `const auto order = compareThreeWay(lhs, rhs);
            return order < 0 ? std::strong_ordering::less
                 : order > 0 ? std::strong_ordering::greater
                             : std::strong_ordering::equal;`;

/** Rewrites the header in place; a no-op once patched or on Qt without the bug. */
export async function patchQtVersionNumber(prefix: string): Promise<void> {
  const header = join(prefix, "include", "QtCore", "qversionnumber.h");
  const source = await Deno.readTextFile(header);
  if (source.includes(oldReturn)) {
    await Deno.writeTextFile(header, source.replace(oldReturn, fixedReturn));
  }
}

if (import.meta.main) {
  if (Deno.args.length !== 1) {
    console.error("usage: qt_version_number_patch.ts <qt-prefix>");
    Deno.exit(2);
  }
  await patchQtVersionNumber(Deno.args[0]);
}
