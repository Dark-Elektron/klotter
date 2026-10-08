package app.darkelektron.klotter

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.AssetManager
import android.graphics.Paint
import android.graphics.Typeface

/**
 * The font Samsung's FlipFont setting has chosen, which Flutter cannot see.
 *
 * Flutter draws with the fonts the system lists in its font configuration.
 * FlipFont leaves those alone: a font chosen in the phone's settings lives in
 * an app of its own, and reaches other apps as [Typeface.DEFAULT], which
 * Flutter never asks for (flutter/flutter#48381). So the font is looked for
 * where it came from, in the font apps a Galaxy phone ships with, by matching
 * each of their fonts against the default typeface, and its file is handed
 * to Flutter to load.
 */
object SystemFont {
    /**
     * The FlipFont apps a Galaxy phone comes with.
     *
     * Android lets an app see another only when it names it, so each is also
     * listed in the manifest's queries, and the two lists have to agree. A font
     * bought from the Galaxy Store comes in an app with a name of its own,
     * which cannot be found without asking to see every app on the phone.
     */
    private val packages = listOf(
        "com.monotype.android.font.rosemary",
        "com.monotype.android.font.foundation",
        "com.monotype.android.font.samsungone",
        "com.monotype.android.font.roboto",
        "com.monotype.android.font.chococooky",
        "com.monotype.android.font.cooljazz",
    )

    /** The chosen font's file, or null when no font app holds it. */
    fun flipFontBytes(context: Context): ByteArray? {
        val wanted = signature(Typeface.DEFAULT)
        val packageManager = context.packageManager
        for (name in packages) {
            val assets = try {
                packageManager.getResourcesForApplication(name).assets
            } catch (e: PackageManager.NameNotFoundException) {
                continue
            }
            for (path in fontFiles(assets)) {
                val typeface = try {
                    Typeface.createFromAsset(assets, path)
                } catch (e: RuntimeException) {
                    continue
                }
                if (signature(typeface) == wanted) {
                    return assets.open(path).use { it.readBytes() }
                }
            }
        }
        return null
    }

    /**
     * Every font file in a font app's assets, at the top or one folder down,
     * which is where FlipFont apps keep them (`fonts/`). Looked for rather than
     * named, since each app names its own files.
     */
    private fun fontFiles(assets: AssetManager): List<String> {
        fun isFont(name: String) =
            name.endsWith(".ttf", ignoreCase = true) ||
                name.endsWith(".otf", ignoreCase = true)

        val found = mutableListOf<String>()
        for (entry in assets.list("").orEmpty()) {
            if (isFont(entry)) {
                found.add(entry)
                continue
            }
            for (inner in assets.list(entry).orEmpty()) {
                if (isFont(inner)) found.add("$entry/$inner")
            }
        }
        return found
    }

    /**
     * What a typeface measures: the width of a line of text and how far it
     * reaches above and below the baseline. Two different fonts all but never
     * agree on all three.
     */
    private fun signature(typeface: Typeface): List<Float> {
        val paint = Paint().apply {
            this.typeface = typeface
            textSize = 100f
        }
        val metrics = paint.fontMetrics
        return listOf(
            paint.measureText("The quick brown fox jumps over the lazy dog 0123456789"),
            metrics.ascent,
            metrics.descent,
        )
    }
}
