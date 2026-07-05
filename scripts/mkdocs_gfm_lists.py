"""Small Markdown extension that accepts GFM-style paragraph-to-list breaks."""

import re

from markdown.extensions import Extension
from markdown.preprocessors import Preprocessor


class GfmListBreakPreprocessor(Preprocessor):
    """Insert a virtual blank line before top-level list items.

    Python-Markdown requires a blank line between a paragraph and a following
    list. GitHub-flavored Markdown renderers commonly accept the tighter form:

        paragraph
        - item

    This preprocessor keeps source documents untouched while making MkDocs
    render that common style as a list.
    """

    FENCE_RE = re.compile(r"^\s*(```+|~~~+)")
    LIST_RE = re.compile(r"^( {0,3})(?:[-+*]|\d+[.)])\s+")

    def run(self, lines):
        output = []
        in_fence = False

        for line in lines:
            if self.FENCE_RE.match(line):
                in_fence = not in_fence
                output.append(line)
                continue

            if (
                not in_fence
                and self.LIST_RE.match(line)
                and output
                and output[-1].strip()
                and not self.LIST_RE.match(output[-1])
            ):
                output.append("")

            output.append(line)

        return output


class GfmListsExtension(Extension):
    def extendMarkdown(self, md):
        md.preprocessors.register(
            GfmListBreakPreprocessor(md),
            "gfm_list_breaks",
            27,
        )


def makeExtension(**kwargs):
    return GfmListsExtension(**kwargs)
