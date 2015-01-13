/*******************************************************************************
 * Boost Software License - Version 1.0 - August 17th, 2003
 *
 * Permission is hereby granted, free of charge, to any person or organization
 * obtaining a copy of the software and accompanying documentation covered by
 * this license (the "Software") to use, reproduce, display, distribute,
 * execute, and transmit the Software, and to prepare derivative works of the
 * Software, and to permit third-parties to whom the Software is furnished to
 * do so, all subject to the following:
 *
 * The copyright notices in the Software and this entire statement, including
 * the above license grant, this restriction and the following disclaimer,
 * must be included in all copies of the Software, in whole or in part, and
 * all derivative works of the Software, unless such copies or derivative
 * works are solely in the form of machine-executable object code generated by
 * a source language processor.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
 * FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 ******************************************************************************/

module dfmt;

import std.stdio;

import std.d.lexer;
import std.d.parser;
import std.d.formatter;
import std.d.ast;
import std.array;

int main(string[] args)
{
    ubyte[] buffer;
    if (args.length == 1)
    {
        ubyte[4096] inputBuffer;
        ubyte[] b;
        while (true)
        {
            b = stdin.rawRead(inputBuffer);
            if (b.length)
                buffer ~= b;
            else
                break;
        }
    }
    else
    {
        File f = File(args[1]);
        buffer = new ubyte[](cast(size_t)f.size);
        f.rawRead(buffer);
    }
    LexerConfig config;
    config.stringBehavior = StringBehavior.source;
    config.whitespaceBehavior = WhitespaceBehavior.skip;
    LexerConfig parseConfig;
    parseConfig.stringBehavior = StringBehavior.source;
    parseConfig.whitespaceBehavior = WhitespaceBehavior.skip;
    StringCache cache = StringCache(StringCache.defaultBucketCount);
    ASTInformation astInformation;
    FormatterConfig formatterConfig;
    auto parseTokens = getTokensForParser(buffer, parseConfig, &cache);
    auto mod = parseModule(parseTokens, args.length > 1 ? args[1] : "stdin");
    auto visitor = new FormatVisitor(&astInformation);
    visitor.visit(mod);
    astInformation.cleanup();
    auto tokens = byToken(buffer, config, &cache).array();
    auto tokenFormatter = TokenFormatter(tokens, stdout, &astInformation,
        &formatterConfig);
    tokenFormatter.format();
    return 0;
}

struct TokenFormatter
{
    this(const(Token)[] tokens, File output, ASTInformation* astInformation,
        FormatterConfig* config)
    {
        this.tokens = tokens;
        this.output = output;
        this.astInformation = astInformation;
        this.config = config;
    }

    void format()
    {
        while (index < tokens.length)
            formatStep();
    }

    invariant
    {
        assert (indentLevel >= 0);
    }

private:

    void formatStep()
    {
        import std.range:assumeSorted;

        assert (index < tokens.length);
        if (current.type == tok!"comment")
        {
            writeToken();
            newline();
        }
        else if (isStringLiteral(current.type) || isNumberLiteral(current.type)
            || current.type == tok!"characterLiteral")
        {
            writeToken();
        }
        else if (current.type == tok!"module" || current.type == tok!"import")
        {
            auto t = current.type;
            writeToken();
            write(" ");
            while (index < tokens.length)
            {
                if (current.type == tok!";")
                {
                    formatStep();
                    if (!(t == tok!"import" && current.type == tok!"import"))
                        newline();
                    break;
                }
                else
                    formatStep();
            }
        }
        else if (current.type == tok!"switch")
            formatSwitch();
        else if (current.type == tok!"for" || current.type == tok!"foreach"
            || current.type == tok!"foreach_reverse" || current.type == tok!"while"
            || current.type == tok!"if")
        {
            currentLineLength += currentTokenLength() + 1;
            writeToken();
            write(" ");
            writeParens();
            if (current.type != tok!"{" && current.type != tok!";")
            {
                pushIndent();
                newline();
            }
        }
        else if (isKeyword(current.type))
        {
            switch (current.type)
            {
            case tok!"default":
            case tok!"cast":
                writeToken();
                break;
            case tok!"mixin":
                writeToken();
                write(" ");
                break;
            default:
                if (index + 1 < tokens.length)
                {
                    auto next = tokens[index + 1];
                    if (next.type == tok!";" || next.type == tok!"("
                        || next.type == tok!")" || next.type == tok!","
                        || next.type == tok!"{")
                    {
                        writeToken();
                    }
                    else
                    {
                        writeToken();
                        write(" ");
                    }
                }
                else
                    writeToken();
                break;
            }
        }
        else if (isBasicType(current.type))
        {
            writeToken();
            if (current.type == tok!"identifier" || isKeyword(current.type))
                write(" ");
        }
        else if (isOperator(current.type))
        {
            switch (current.type)
            {
            case tok!"*":
                if (!assumeSorted(astInformation.spaceAfterLocations).equalRange(current.index).empty)
                {
                    writeToken();
                    write(" ");
                    break;
                }
                goto case;
            case tok!"~":
            case tok!"&":
            case tok!"+":
            case tok!"-":
                if (!assumeSorted(astInformation.unaryLocations)
                    .equalRange(current.index).empty)
                {
                    writeToken();
                    break;
                }
                goto binary;
            case tok!"(":
                writeParens();
                break;
            case tok!"@":
            case tok!"!":
            case tok!"...":
            case tok!"[":
            case tok!"++":
            case tok!"--":
            case tok!"$":
            case tok!":":
                writeToken();
                break;
            case tok!"]":
                writeToken();
                if (current.type == tok!"identifier")
                    write(" ");
                break;
            case tok!";":
                tempIndent = 0;
                writeToken();
                newline();
                break;
            case tok!"{":
                writeBraces();
                break;
            case tok!".":
                if (currentLineLength + nextTokenLength() >= config.columnSoftLimit)
                {
                    pushIndent();
                    newline();
                    writeToken();
                }
                else
                    writeToken();
                break;
            case tok!",":
                if (currentLineLength + nextTokenLength() >= config.columnSoftLimit)
                {
                    pushIndent();
                    writeToken();
                    newline();
                }
                else
                {
                    writeToken();
                    write(" ");
                }
                break;
            case tok!"^^":
            case tok!"^=":
            case tok!"^":
            case tok!"~=":
            case tok!"<<=":
            case tok!"<<":
            case tok!"<=":
            case tok!"<>=":
            case tok!"<>":
            case tok!"<":
            case tok!"==":
            case tok!"=>":
            case tok!"=":
            case tok!">=":
            case tok!">>=":
            case tok!">>>=":
            case tok!">>>":
            case tok!">>":
            case tok!">":
            case tok!"|=":
            case tok!"||":
            case tok!"|":
            case tok!"-=":
            case tok!"!<=":
            case tok!"!<>=":
            case tok!"!<>":
            case tok!"!<":
            case tok!"!=":
            case tok!"!>=":
            case tok!"!>":
            case tok!"?":
            case tok!"/=":
            case tok!"/":
            case tok!"..":
            case tok!"*=":
            case tok!"&=":
            case tok!"&&":
            case tok!"%=":
            case tok!"%":
            case tok!"+=":
            binary:
                if (currentLineLength + nextTokenLength() >= config.columnSoftLimit)
                {
                    pushIndent();
                    newline();
                }
                else
                    write(" ");
                writeToken();
                write(" ");
                break;
            default:
                assert (false, str(current.type));
            }
        }
        else if (current.type == tok!"identifier")
        {
            writeToken();
            if (current.type == tok!"identifier")
                write(" ");
        }
        else
            assert (false, str(current.type));
    }

	/// Pushes a temporary indent level
    void pushIndent()
    {
        if (tempIndent == 0)
            tempIndent++;
    }

	/// Pops a temporary indent level
    void popIndent()
    {
        if (tempIndent > 0)
            tempIndent--;
    }

	/// Writes balanced braces
    void writeBraces()
    {
        import std.range : assumeSorted;
        int depth = 0;
        do
        {
            if (current.type == tok!"{")
            {
                depth++;
                if (config.braceStyle == BraceStyle.otbs)
                {
                    write(" ");
                    write("{");
                }
                else
                {
                    newline();
                    write("{");
                }
                indentLevel++;
                index++;
                newline();
            }
            else if (current.type == tok!"}")
            {
				// Silly hack to format enums better.
                if (peekBackIs(tok!"identifier"))
                    newline();
                write("}");
                depth--;
                if (index < tokens.length &&
                    assumeSorted(astInformation.doubleNewlineLocations)
                    .equalRange(tokens[index].index).length)
                {
                    output.write("\n");
                }
                if (config.braceStyle == BraceStyle.otbs)
                {
                    index++;
                    if (index < tokens.length && current.type == tok!"else")
                        write(" ");
                    else
                    {
                        if (peekIs(tok!"case") || peekIs(tok!"default"))
                            indentLevel--;
                        newline();
                    }
                }
                else
                {
                    index++;
                    if (peekIs(tok!"case") || peekIs(tok!"default"))
                        indentLevel--;
                    newline();
                }
            }
            else
                formatStep();
        }
        while (index < tokens.length && depth > 0);
        popIndent();
    }

    void writeParens()
    in
    {
        assert (current.type == tok!"(", str(current.type));
    }
    body
    {
        immutable t = tempIndent;
        int depth = 0;
        do
        {
            if (current.type == tok!";")
            {
                write("; ");
                currentLineLength += 2;
                index++;
                continue;
            }
            else if (current.type == tok!"(")
            {
                writeToken();
                depth++;
                continue;
            }
            else if (current.type == tok!")")
            {
                if (peekIs(tok!"identifier") || (index + 1 < tokens.length
                    && isKeyword(tokens[index + 1].type)))
                {
                    writeToken();
                    write(" ");
                }
                else
                    writeToken();
                depth--;
            }
            else
                formatStep();
        }
        while (index < tokens.length && depth > 0);
        popIndent();
        tempIndent = t;
    }

    bool peekIsLabel()
    {
        return peekIs(tok!"identifier") && peek2Is(tok!":");
    }

    void formatSwitch()
    {
        immutable l = indentLevel;
        writeToken(); // switch
        write(" ");
        writeParens();
        if (current.type != tok!"{")
            return;
        if (config.braceStyle == BraceStyle.otbs)
            write(" ");
        else
            newline();
        writeToken();
        newline();
        while (index < tokens.length)
        {
            if (current.type == tok!"case")
            {
                writeToken();
                write(" ");
            }
            else if (current.type == tok!":")
            {
                if (peekIs(tok!".."))
                {
                    writeToken();
                    write(" ");
                    writeToken();
                    write(" ");
                }
                else
                {
                    if (!(peekIs(tok!"case") || peekIs(tok!"default") || peekIsLabel()))
                        indentLevel++;
                    formatStep();
                    newline();
                }
            }
            else
            {
                assert (current.type != tok!"}");
                if (peekIs(tok!"case") || peekIs(tok!"default") || peekIsLabel())
                {
                    indentLevel = l;
                    formatStep();
                }
                else
                {
                    formatStep();
                    if (current.type == tok!"}")
                        break;
                }
            }
        }
        indentLevel = l;
        assert (current.type == tok!"}");
        writeToken();
        newline();
    }

    int currentTokenLength()
    {
        switch (current.type)
        {
        mixin (generateFixedLengthCases());
        default: return cast(int) current.text.length;
        }
    }

    int nextTokenLength()
    {
        import std.algorithm : countUntil;
        if (index + 1 >= tokens.length)
            return INVALID_TOKEN_LENGTH;
        auto nextToken = tokens[index + 1];
        switch (nextToken.type)
        {
        case tok!"identifier":
        case tok!"stringLiteral":
        case tok!"wstringLiteral":
        case tok!"dstringLiteral":
            return cast(int) nextToken.text.countUntil('\n');
        mixin (generateFixedLengthCases());
        default: return -1;
        }
    }

    ref current() const @property
    in
    {
        assert (index < tokens.length);
    }
    body
    {
        return tokens[index];
    }

    bool peekBackIs(IdType tokenType)
    {
        return (index >= 1) && tokens[index - 1].type == tokenType;
    }

    bool peekImplementation(IdType tokenType, size_t n)
    {
        auto i = index + n;
        while (i < tokens.length && tokens[i].type == tok!"comment")
            i++;
        return i < tokens.length && tokens[i].type == tokenType;
    }

    bool peek2Is(IdType tokenType)
    {
        return peekImplementation(tokenType, 2);
    }

    bool peekIs(IdType tokenType)
    {
        return peekImplementation(tokenType, 1);
    }

    void newline()
    {
        output.write("\n");
        currentLineLength = 0;
        if (index < tokens.length)
        {
            if (current.type == tok!"}")
                indentLevel--;
            indent();
        }
    }

    void write(string str)
    {
        currentLineLength += str.length;
        output.write(str);
    }

    void writeToken()
    {
        currentLineLength += currentTokenLength();
        if (current.text is null)
            output.write(str(current.type));
        else
            output.write(current.text);
        index++;
    }

    void indent()
    {
        import std.range : repeat, take;
        if (config.useTabs)
            foreach (i; 0 .. indentLevel + tempIndent)
            {
                currentLineLength += config.tabSize;
                output.write("\t");
            }
        else
            foreach (i; 0 .. indentLevel + tempIndent)
                foreach (j; 0 .. config.indentSize)
                {
                    output.write(" ");
                    currentLineLength++;
                }
    }

    /// Length of an invalid token
    enum int INVALID_TOKEN_LENGTH = -1;

    /// Current index into the tokens array
    size_t index;

    /// Current indent level
    int indentLevel;

    /// Current temproray indententation level;
    int tempIndent;

    /// Length of the current line (so far)
    uint currentLineLength = 0;

    /// File to output to
    File output;

    /// Tokens being formatted
    const(Token)[] tokens;

    /// Information about the AST
    ASTInformation* astInformation;

    /// Configuration
    FormatterConfig* config;
}

/// The only good brace styles
enum BraceStyle
{
    allman,
    otbs
}

/// Configuration options for formatting
struct FormatterConfig
{
    /// Number of spaces used for indentation
    uint indentSize = 4;

    /// Use tabs or spaces
    bool useTabs = false;

    /// Size of a tab character
    uint tabSize = 8;

    /// Soft line wrap limit
    uint columnSoftLimit = 80;

    /// Hard line wrap limit
    uint columnHardLimit = 120;

    /// Use the One True Brace Style
    BraceStyle braceStyle = BraceStyle.allman;
}

///
struct ASTInformation
{
    /// Sorts the arrays so that binary search will work on them
    void cleanup()
    {
        import std.algorithm : sort;
        sort(doubleNewlineLocations);
        sort(spaceAfterLocations);
        sort(unaryLocations);
    }

    /// Locations of end braces for struct bodies
    size_t[] doubleNewlineLocations;

    /// Locations of tokens where a space is needed (such as the '*' in a type)
    size_t[] spaceAfterLocations;

    /// Locations of unary operators
    size_t[] unaryLocations;
}

/// Collects information from the AST that is useful for the formatter
final class FormatVisitor : ASTVisitor
{
    ///
    this(ASTInformation* astInformation)
    {
        this.astInformation = astInformation;
    }

    override void visit(const FunctionBody functionBody)
    {
        if (functionBody.blockStatement !is null)
            astInformation.doubleNewlineLocations ~= functionBody.blockStatement.endLocation;
        if (functionBody.inStatement !is null && functionBody.inStatement.blockStatement !is null)
            astInformation.doubleNewlineLocations ~= functionBody.inStatement.blockStatement.endLocation;
        if (functionBody.outStatement !is null && functionBody.outStatement.blockStatement !is null)
            astInformation.doubleNewlineLocations ~= functionBody.outStatement.blockStatement.endLocation;
        if (functionBody.bodyStatement !is null && functionBody.bodyStatement.blockStatement !is null)
            astInformation.doubleNewlineLocations ~= functionBody.bodyStatement.blockStatement.endLocation;
        functionBody.accept(this);
    }

    override void visit(const EnumBody enumBody)
    {
        astInformation.doubleNewlineLocations ~= enumBody.endLocation;
        enumBody.accept(this);
    }

    override void visit(const Unittest unittest_)
    {
        astInformation.doubleNewlineLocations ~= unittest_.blockStatement.endLocation;
        unittest_.accept(this);
    }

    override void visit(const Invariant invariant_)
    {
        astInformation.doubleNewlineLocations ~= invariant_.blockStatement.endLocation;
        invariant_.accept(this);
    }

    override void visit(const StructBody structBody)
    {
        astInformation.doubleNewlineLocations ~= structBody.endLocation;
        structBody.accept(this);
    }

    override void visit(const TemplateDeclaration templateDeclaration)
    {
        astInformation.doubleNewlineLocations ~= templateDeclaration.endLocation;
        templateDeclaration.accept(this);
    }

    override void visit(const TypeSuffix typeSuffix)
    {
        if (typeSuffix.star.type != tok!"")
            astInformation.spaceAfterLocations ~= typeSuffix.star.index;
        typeSuffix.accept(this);
    }

    override void visit(const UnaryExpression unary)
    {
        if (unary.prefix.type == tok!"~" || unary.prefix.type == tok!"&"
            || unary.prefix.type == tok!"*" || unary.prefix.type == tok!"+"
            || unary.prefix.type == tok!"-")
        {
            astInformation.unaryLocations ~= unary.prefix.index;
        }
        unary.accept(this);
    }

private:
    ASTInformation* astInformation;
    alias visit = ASTVisitor.visit;
}

string generateFixedLengthCases()
{
    import std.algorithm:map;
    import std.string:format;

    string[] fixedLengthTokens = [
    "abstract", "alias", "align", "asm", "assert", "auto", "body", "bool",
    "break", "byte", "case", "cast", "catch", "cdouble", "cent", "cfloat",
    "char", "class", "const", "continue", "creal", "dchar", "debug", "default",
    "delegate", "delete", "deprecated", "do", "double", "else", "enum",
    "export", "extern", "false", "final", "finally", "float", "for", "foreach",
    "foreach_reverse", "function", "goto", "idouble", "if", "ifloat",
    "immutable", "import", "in", "inout", "int", "interface", "invariant",
    "ireal", "is", "lazy", "long", "macro", "mixin", "module", "new", "nothrow",
    "null", "out", "override", "package", "pragma", "private", "protected",
    "public", "pure", "real", "ref", "return", "scope", "shared", "short",
    "static", "struct", "super", "switch", "synchronized", "template", "this",
    "throw", "true", "try", "typedef", "typeid", "typeof", "ubyte", "ucent",
    "uint", "ulong", "union", "unittest", "ushort", "version", "void",
    "volatile", "wchar", "while", "with", "__DATE__", "__EOF__", "__FILE__",
    "__FUNCTION__", "__gshared", "__LINE__", "__MODULE__", "__parameters",
    "__PRETTY_FUNCTION__", "__TIME__", "__TIMESTAMP__", "__traits", "__vector",
    "__VENDOR__", "__VERSION__", ",", ".", "..", "...", "/", "/=", "!", "!<",
    "!<=", "!<>", "!<>=", "!=", "!>", "!>=", "$", "%", "%=", "&", "&&", "&=",
    "(", ")", "*", "*=", "+", "++", "+=", "-", "--", "-=", ":", ";", "<", "<<",
    "<<=", "<=", "<>", "<>=", "=", "==", "=>", ">", ">=", ">>", ">>=", ">>>",
    ">>>=", "?", "@", "[", "]", "^", "^=", "^^", "^^=", "{", "|", "|=", "||",
    "}", "~", "~="
    ];

    return fixedLengthTokens.map!(a => format(`case tok!"%s": return %d;`, a, a.length)).join("\n\t");
}
