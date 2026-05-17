import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SCANNER = ROOT / "scanner"
ALL_KEYWORDS = [
    "array",
    "boolean",
    "begin",
    "case",
    "const",
    "continue",
    "do",
    "downto",
    "else",
    "end",
    "exit",
    "for",
    "function",
    "goto",
    "if",
    "in",
    "integer",
    "loop",
    "of",
    "procedure",
    "program",
    "repeat",
    "return",
    "real",
    "string",
    "then",
    "to",
    "type",
    "until",
    "var",
    "while",
    "write",
    "writeln",
    "mod",
    "and",
    "or",
    "not",
]


def build():
    subprocess.run(["make"], cwd=ROOT, check=True, capture_output=True, text=True)


def run_scanner(source: str) -> str:
    build()
    result = subprocess.run(
        [str(SCANNER)],
        cwd=ROOT,
        input=source,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def run_scanner_file(source: str) -> str:
    build()
    fixture = ROOT / "tests" / "tmp_input.pas"
    fixture.parent.mkdir(exist_ok=True)
    fixture.write_text(source)
    result = subprocess.run(
        [str(SCANNER), str(fixture)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def test_keywords_identifiers_and_symbol_table():
    output = run_scanner(
        "program Demo\n"
        "var alpha alpha1 beginX\n"
        "begin\n"
        "write(alpha);\n"
        "end\n"
    )

    lines = output.splitlines()
    assert lines[0] == "<PROGRAM>"
    assert lines[1] == "<id: Demo>"
    assert lines[2] == "1: program Demo"
    assert "2: var alpha alpha1 beginX" in output
    assert "<PROGRAM>" in output
    assert "<VAR>" in output
    assert "<BEGIN>" in output
    assert "<WRITE>" in output
    assert "<id: Demo>" in output
    assert "<id: alpha>" in output
    assert "<id: alpha1>" in output
    assert "<id: beginX>" in output
    assert "\nSymbol Table:" in output
    assert "\nDemo\n" in output
    assert "\nalpha\n" in output
    assert output.count("\nalpha\n") == 1


def test_delimiters_and_operators():
    output = run_scanner(", : . ; ( ) [ ] + - * / := < <= >= > = <> mod and or not")

    for token in [
        "<','>",
        "<':'>",
        "<'.'>",
        "<';'>",
        "<'('>",
        "<')'>",
        "<'['>",
        "<']'>",
        "<'+'>",
        "<'-'>",
        "<'*'>",
        "<'/'>",
        "<ASSIGN>",
        "<LT>",
        "<LE>",
        "<GE>",
        "<GT>",
        "<EQ>",
        "<NE>",
        "<MOD>",
        "<AND>",
        "<OR>",
        "<NOT>",
    ]:
        assert token in output
    assert "1: , : . ; ( ) [ ] + - * / := < <= >= > = <> mod and or not" in output


def test_all_keywords_are_recognized_case_insensitively():
    source = " ".join(word.capitalize() for word in ALL_KEYWORDS)
    output = run_scanner(source)

    for token in [
        "<ARRAY>",
        "<BOOLEAN>",
        "<BEGIN>",
        "<CASE>",
        "<CONST>",
        "<CONTINUE>",
        "<DO>",
        "<DOWNTO>",
        "<ELSE>",
        "<END>",
        "<EXIT>",
        "<FOR>",
        "<FUNCTION>",
        "<GOTO>",
        "<IF>",
        "<IN>",
        "<INTEGER>",
        "<LOOP>",
        "<OF>",
        "<PROCEDURE>",
        "<PROGRAM>",
        "<REPEAT>",
        "<RETURN>",
        "<REAL>",
        "<STRING>",
        "<THEN>",
        "<TO>",
        "<TYPE>",
        "<UNTIL>",
        "<VAR>",
        "<WHILE>",
        "<WRITE>",
        "<WRITELN>",
        "<MOD>",
        "<AND>",
        "<OR>",
        "<NOT>",
    ]:
        assert token in output


def test_constants_and_comments():
    output = run_scanner(
        "true false 0 123 3.14 +2.3E10 -0.5 \"aa\"\"bb\" // drop me\n"
        "(* multi\n"
        "line comment *) \"Hello World\"\n"
    )

    assert "<boolean:true>" in output
    assert "<boolean:false>" in output
    assert "<integer:0>" in output
    assert "<integer:123>" in output
    assert "<real:3.14>" in output
    assert "<'+'>" in output
    assert "<real:2.3E10>" in output
    assert "<'-'>" in output
    assert "<real:0.5>" in output
    assert "<string:aa\"bb>" in output
    assert "<string:Hello World>" in output
    assert "1: true false 0 123 3.14 +2.3E10 -0.5 \"aa\"\"bb\" // drop me" in output
    assert "2: (* multi" in output
    assert "3: line comment *) \"Hello World\"" in output


def test_invalid_inputs_report_line_numbers():
    output = run_scanner(
        "write(@);\n"
        "\"hello\n"
        "3.4.5\n"
    )

    assert "line 1: illegal character '@'" in output
    assert "line 2: unterminated string" in output
    assert "line 3: invalid number '3.4.5'" in output


def test_case_insensitive_keywords_and_identifier_case_sensitivity():
    output = run_scanner("Program Demo True false")

    assert "<PROGRAM>" in output
    assert "<id: Demo>" in output
    assert "<boolean:True>" in output
    assert "<boolean:false>" in output


def test_identifier_boundaries_and_symbol_table_case_sensitivity():
    output = run_scanner("abc a1b2 1abc Alpha alpha ALPHA")

    assert "<id: abc>" in output
    assert "<id: a1b2>" in output
    assert "<integer:1>" in output
    assert output.count("<id: abc>") == 2
    assert "\nAlpha\n" in output
    assert "\nalpha\n" in output
    assert "\nALPHA\n" in output


def test_empty_string_and_multiple_escaped_quotes():
    output = run_scanner("\"\" \"a\"\"b\"\"c\"")

    assert "<string:>" in output
    assert "<string:a\"b\"c>" in output


def test_unterminated_comment_reports_error():
    output = run_scanner("begin\n(* comment")

    assert "<BEGIN>" in output
    assert "1: begin" in output
    assert "line 2: unterminated comment" in output


def test_comment_precedence_examples_from_pdf():
    output = run_scanner(
        "// a comment // line *( )* with (* delimiters *) before the end\n"
        "(* this is a comment // line with some (* and\n"
        "C delimiters *)\n"
    )

    assert "1: // a comment // line *( )* with (* delimiters *) before the end" in output
    assert "2: (* this is a comment // line with some (* and" in output
    assert "3: C delimiters *)" in output
    token_section = output.split("\nSymbol Table:")[0]
    assert "<" not in token_section


def test_brace_style_comments_are_discarded():
    output = run_scanner("{ Mail Statements }\nwrite(1);\n")

    assert "1: { Mail Statements }" in output
    assert "2: write(1);" in output
    assert "<WRITE>" in output
    assert "<integer:1>" in output
    assert "\nMail\n" not in output
    assert "\nStatements\n" not in output


def test_teacher_hello_world_sample():
    source = (
        "(* Hello World Example *)\n"
        "program HelloWorld;\n"
        "\n"
        "{ Mail Statements }\n"
        "begin\n"
        "  // Print text to the console\n"
        "  write (\"Hello World\");\n"
        "end HelloWorld.\n"
    )

    output = run_scanner(source)

    assert "<PROGRAM>" in output
    assert "<id: HelloWorld>" in output
    assert "<BEGIN>" in output
    assert "<WRITE>" in output
    assert "4: { Mail Statements }" in output
    assert "\nMail\n" not in output
    assert "\nStatements\n" not in output
    assert "\nSymbol Table:\nHelloWorld" in output


def test_teacher_function_sample():
    source = (
        "(*\n"
        " * Example with Functions\n"
        " *)\n"
        "\n"
        "program Example;\n"
        "\n"
        "// constants\n"
        "const a = 5;\n"
        "\n"
        "// variables\n"
        "var c: integer;\n"
        "\n"
        "// function declaration\n"
        "function add(a:integer, b:integer): integer;\n"
        "begin\n"
        "  return a+b;\n"
        "end add;\n"
        "\n"
        "// main function\n"
        "begin\n"
        "  c := add(a, 10);\n"
        "  if (c > 10) then\n"
        "    write -c;\n"
        "  else\n"
        "    write c;\n"
        "  end;\n"
        "  writeln \"Hello World\";\n"
        "end Example.\n"
    )

    output = run_scanner(source)

    for token in ["<FUNCTION>", "<RETURN>", "<IF>", "<THEN>", "<ELSE>", "<WRITELN>"]:
        assert token in output
    for name in ["Example", "a", "c", "add", "b"]:
        assert f"\n{name}\n" in output


def test_sign_is_always_operator_not_part_of_real():
    output = run_scanner("a-0.5 a - 0.5 b+2.0 b + 2.0")

    assert "<id: a>" in output
    assert "<id: b>" in output
    assert "<'-'>" in output
    assert "<'+'>" in output
    assert "<real:0.5>" in output
    assert "<real:2.0>" in output
    assert "<real:-0.5>" not in output
    assert "<real:+2.0>" not in output


def test_negative_integer_constant():
    output = run_scanner(
        "const x = -5;\n"
        "var y: integer;\n"
        "begin\n"
        "  y := x - 3;\n"
        "end\n"
    )

    assert "<CONST>" in output
    assert "<id: x>" in output
    assert "<EQ>" in output
    assert "<integer:-5>" in output

    assert "<id: y>" in output
    assert "<ASSIGN>" in output
    assert "<'-'>" in output
    assert "<integer:3>" in output


def test_multiple_illegal_characters_each_reported():
    output = run_scanner("@#\n$")

    assert "line 1: illegal character '@'" in output
    assert "line 1: illegal character '#'" in output
    assert "line 2: illegal character '$'" in output


def test_file_input_mode_matches_stdin_behavior():
    source = "program Hello\nend"
    output = run_scanner_file(source)

    assert "<PROGRAM>" in output
    assert "<id: Hello>" in output
    assert "<END>" in output
    assert "1: program Hello" in output
    assert "2: end" in output


def test_pdf_hello_world_example_golden_output():
    source = (
        "(* Hello World Example *)\n"
        "program HelloWorld\n"
        "begin\n"
        "// Print text to the console\n"
        "write (\"Hello World\");\n"
        "end HelloWorld.\n"
    )

    output = run_scanner(source)

    expected = "\n".join(
        [
            "1: (* Hello World Example *)",
            "<PROGRAM>",
            "<id: HelloWorld>",
            "2: program HelloWorld",
            "<BEGIN>",
            "3: begin",
            "4: // Print text to the console",
            "<WRITE>",
            "<'('>",
            "<string:Hello World>",
            "<')'>",
            "<';'>",
            "5: write (\"Hello World\");",
            "<END>",
            "<id: HelloWorld>",
            "<'.'>",
            "6: end HelloWorld.",
            "",
            "Symbol Table:",
            "HelloWorld",
        ]
    )

    assert output.strip() == expected

if __name__ == "__main__":
    print("Running tests...")
    print("Testing keywords, identifiers, and symbol table...")
    test_keywords_identifiers_and_symbol_table()
    print("Testing delimiters and operators...")
    test_delimiters_and_operators()
    print("Testing all keywords are recognized case insensitively...")
    test_all_keywords_are_recognized_case_insensitively()
    print("Testing constants and comments...")
    test_constants_and_comments()
    print("Testing invalid inputs report line numbers...")
    test_invalid_inputs_report_line_numbers()
    print("Testing case insensitive keywords and identifier case sensitivity...")
    test_case_insensitive_keywords_and_identifier_case_sensitivity()
    print("Testing identifier boundaries and symbol table case sensitivity...")
    test_identifier_boundaries_and_symbol_table_case_sensitivity()
    print("Testing empty string and multiple escaped quotes...")
    test_empty_string_and_multiple_escaped_quotes()
    print("Testing unterminated comment reports error...")
    test_unterminated_comment_reports_error()
    print("Testing comment precedence examples from PDF...")
    test_comment_precedence_examples_from_pdf()
    print("Testing brace style comments are discarded...")
    test_brace_style_comments_are_discarded()
    print("Testing teacher hello world sample...")
    test_teacher_hello_world_sample()
    print("Testing teacher function sample...")
    test_teacher_function_sample()
    print("Testing sign is always operator not part of real...")
    test_sign_is_always_operator_not_part_of_real()
    print("Testing negative integer constant...")
    test_negative_integer_constant()
    print("Testing multiple illegal characters each reported...")
    test_multiple_illegal_characters_each_reported()
    print("Testing file input mode matches stdin behavior...")
    test_file_input_mode_matches_stdin_behavior()
    print("Testing PDF hello world example golden output...")
    test_pdf_hello_world_example_golden_output()
    print("All tests passed!")