//          Copyright Brian Schott 2015.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module dfmt.config;

import dfmt.editorconfig;

/// Brace styles
enum BraceStyle
{
    unspecified,
    /// $(LINK https://en.wikipedia.org/wiki/Indent_style#Allman_style)
    allman,
    /// $(LINK https://en.wikipedia.org/wiki/Indent_style#Variant:_1TBS)
    otbs,
    /// $(LINK https://en.wikipedia.org/wiki/Indent_style#Variant:_Stroustrup)
    stroustrup
}

/// Configuration options for formatting
struct Config
{
    ///
    OptionalBoolean dfmt_align_switch_statements = OptionalBoolean.t;
    ///
    BraceStyle dfmt_brace_style = BraceStyle.allman;
    ///
    OptionalBoolean dfmt_outdent_attributes = OptionalBoolean.t;
    ///
    OptionalBoolean dfmt_outdent_labels = OptionalBoolean.t;
    ///
    int dfmt_soft_max_line_length = 80;
    ///
    OptionalBoolean dfmt_space_after_cast = OptionalBoolean.t;
    ///
    OptionalBoolean dfmt_space_after_keywords = OptionalBoolean.t;
    ///
    OptionalBoolean dfmt_split_operator_at_line_end = OptionalBoolean.f;

    mixin StandardEditorConfigFields;


    /**
     * Initializes the standard EditorConfig properties with default values that
     * make sense for D code.
     */
    void initializeWithDefaults()
    {
		pattern = "*.d";
        end_of_line = EOL.lf;
        indent_style = IndentStyle.space;
        indent_size = 4;
        tab_width = 4;
        max_line_length = 120;
    }

    /**
     * Returns:
     *     true if the configuration is valid
     */
    bool isValid()
    {
        import std.stdio : stderr;

        if (dfmt_soft_max_line_length > max_line_length)
        {
            stderr.writeln("Column hard limit must be greater than or equal to column soft limit");
            return false;
        }
        return true;
    }
}
