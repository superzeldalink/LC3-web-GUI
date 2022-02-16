import 'dart:convert';
import 'dart:io';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:clipboard/clipboard.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:js' as js;
import 'vm.dart';
import 'disassemble.dart' as disassembler;
import 'package:responsive_framework/responsive_framework.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LC3 (de)Compiler and VM',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ResponsiveWrapper.builder(
        const MyHomePage(title: 'LC3 (de)Compiler and VM'),
        defaultScaleFactor: 0.7,
        minWidth: 1102,
        defaultScale: true,
        breakpoints: [
          const ResponsiveBreakpoint.resize(1102, scaleFactor: 0.7),
          const ResponsiveBreakpoint.resize(1258, scaleFactor: 0.8),
          const ResponsiveBreakpoint.resize(1416, scaleFactor: 0.9),
          const ResponsiveBreakpoint.resize(1572),
          // ResponsiveBreakpoint.autoScale(1920, scaleFactor: 1),
        ],
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late List instructions = [];
  // TextEditingController codeFieldController = TextEditingController();
  CodeController codeFieldController = CodeController(
    text: '.ORIG x3000\n\n.END',
    webSpaceFix: true,
    patternMap: {
      r"ADD|AND|NOT|LDI|LDR|LD|LEA|STI|STR|ST|JMP|RET|BR|JSRR|JSR|RTI|TRAP|add|and|not|ldi|ldr|ld|lea|st|str|sti|jmp|ret|br|jsrr|jsr|rti|trap|Add|And|Not|Ld|Ldi|Ldr|Lea|St|Sti|Str|Jmp|Ret|Br|Jsr|Jsrr|Rti|Trap":
          const TextStyle(color: Color(0xff0c3fed)),
      r"x[0-9A-Za-z]{1,4}|#[\-0-9]*": const TextStyle(color: Color(0xff06910F)),
      r"[R|r][0-7]": const TextStyle(color: Color(0xffe65100)),
      r";.*": const TextStyle(color: Color(0xff007400)),
      r"\.[^ ·\n]*": const TextStyle(color: Color(0xffC41A16)),
    },
  );
  TextEditingController consoleController = TextEditingController();
  TextEditingController inputController = TextEditingController();
  TextEditingController logController = TextEditingController();
  TextEditingController fileNameController = TextEditingController();

  @override
  void initState() {
    initMachine();
    super.initState();
  }

  initMachine() {
    setState(() {
      register[RegisterAddress.R_R0] = 0;
      register[RegisterAddress.R_R1] = 0;
      register[RegisterAddress.R_R2] = 0;
      register[RegisterAddress.R_R3] = 0;
      register[RegisterAddress.R_R4] = 0;
      register[RegisterAddress.R_R5] = 0;
      register[RegisterAddress.R_R6] = 0;
      register[RegisterAddress.R_R7] = 0;
      register[RegisterAddress.R_PC] = (start != null) ? start : 12288;

      if (countInst != null) countInst = List.filled(countInst.length, 0);
    });
  }

  var isRunning = false;
  var compiled = false;

  var obj;
  int start = 0x3000;
  int end = 0;
  bool stepping = false;
  bool haltFound = false;

  var countInst;

  void compile() {
    setState(() {
      compiled = false;
      logController.text = '';

      var input = codeFieldController.rawText;
      var asm = '';
      LineSplitter ls = const LineSplitter();
      List<String> lines = ls.convert(input);

      for (var i = 0; i < lines.length; i++) {
        asm += '${lines[i]}\n';
      }
      obj = js.context.callMethod('Run', [asm]);

      if (obj[0] == 'error') {
        for (var i = 1; i < obj.length; i++) {
          logController.text += obj[i].toString();
        }
        logController.text += '\n';
      } else if (obj == null) {
      } else {
        logController.text = 'Compiled\n';

        start = int.parse(
            obj[0].toRadixString(16).padLeft(2, '0') +
                obj[1].toRadixString(16).padLeft(2, '0'),
            radix: 16);
        end = (start + (obj.length / 2) - 1) as int;

        read_obj(obj);
        instructions = disassembler.disassembleByMem(start, end);

        countInst = List.filled(instructions.length, 0);

        compiled = true;
      }
    });
  }

  void stepNext() {
    setState(() {
      if (obj == null) read_obj(obj);
      var pc = register[RegisterAddress.R_PC]!;
      var instr = mem_read(pc);
      countInst[pc - start]++;
      var op = Opcode.values[instr >> 12];
      var trap = TrapConverter.from(instr & 0xFF);

      var nextInstr = mem_read(pc + 1);
      var nextOp = Opcode.values[nextInstr >> 12];
      var nextTrap = TrapConverter.from(nextInstr & 0xFF);
      if ((op == Opcode.OP_TRAP && trap == Trap.TRAP_HALT)) {
        haltFound = true;
        isRunning = false;
      } else if (pc >= end && haltFound == false) {
        isRunning = false;
        logController.text += '"TRAP x25" (HALT) should be added.\n';
      } else if (countInst.indexWhere((int a) => (a > 0xFFFF)) != -1) {
        isRunning = false;
        logController.text += 'Error: Infinite loop encountered!\n';
      }

      step(consoleController, inputController);
      if (nextOp == Opcode.OP_TRAP) {
        if (nextTrap == Trap.TRAP_IN) {
          insertText('Enter a character: ', consoleController);
          isRunning = false;
        } else if (nextTrap == Trap.TRAP_GETC) {
          isRunning = false;
        }
      }
    });
  }

  void run() {
    if (obj == null) read_obj(obj);
    isRunning = true;

    while (isRunning) {
      stepNext();
    }
  }

  DataTable memRegisters() {
    return DataTable(
      showCheckboxColumn: false,
      columnSpacing: 10.0,
      dataRowHeight: 25.0,
      headingRowHeight: 0,
      columns: [
        DataColumn(label: Container()),
        DataColumn(
            label: Container(
          width: 50.0,
        )),
        DataColumn(label: Container()),
        // DataColumn(label: Container()),
        // DataColumn(label: Container()),
      ],
      rows: List.generate(9, (i) {
        var text, regAddress, value, hex;
        switch (i) {
          case 0:
            {
              text = 'R0';
              regAddress = RegisterAddress.R_R0;
            }
            break;

          case 1:
            {
              text = 'R1';
              regAddress = RegisterAddress.R_R1;
            }
            break;

          case 2:
            {
              text = 'R2';
              regAddress = RegisterAddress.R_R2;
            }
            break;

          case 3:
            {
              text = 'R3';
              regAddress = RegisterAddress.R_R3;
            }
            break;

          case 4:
            {
              text = 'R4';
              regAddress = RegisterAddress.R_R4;
            }
            break;

          case 5:
            {
              text = 'R5';
              regAddress = RegisterAddress.R_R5;
            }
            break;

          case 6:
            {
              text = 'R6';
              regAddress = RegisterAddress.R_R6;
            }
            break;

          case 7:
            {
              text = 'R7';
              regAddress = RegisterAddress.R_R7;
            }
            break;

          case 8:
            {
              text = 'PC';
              regAddress = RegisterAddress.R_PC;
            }
            break;
        }

        value = register[regAddress];
        hex = value
            .toUnsigned(16)
            .toRadixString(16)
            .toUpperCase()
            .padLeft(4, '0');
        return DataRow(
          onSelectChanged: (selected) {
            var hexController = TextEditingController(text: hex);
            var decController =
                TextEditingController(text: value.toSigned(16).toString());

            showDialog<void>(
              context: context,
              builder: (BuildContext context) {
                return StatefulBuilder(builder: (context, setDialogState) {
                  return AlertDialog(
                    title: Text('Change value of $text'),
                    content: SingleChildScrollView(
                      child: Column(
                        children: [
                          TextField(
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 20,
                            ),
                            maxLength: 4,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[a-fA-F0-9]')),
                            ],
                            controller: hexController,
                            decoration: const InputDecoration(
                              border: UnderlineInputBorder(),
                              labelText: 'Hexadecimal value',
                              counterText: '',
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == '') {
                                  decController.text = '';
                                } else {
                                  decController.text =
                                      int.parse(value, radix: 16)
                                          .toSigned(16)
                                          .toString();
                                }
                              });
                            },
                          ),
                          TextField(
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 20,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[-0-9]')),
                            ],
                            controller: decController,
                            decoration: const InputDecoration(
                              border: UnderlineInputBorder(),
                              labelText: 'Decimal value',
                              counterText: '',
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == '' || value == '-') {
                                  hexController.text = '';
                                } else if (int.parse(value) > 32767) {
                                  decController.text = '32767';
                                  hexController.text = '7FFF';
                                } else if (int.parse(value) < -32768) {
                                  decController.text = '-32768';
                                  hexController.text = '8000';
                                } else {
                                  hexController.text = int.parse(value)
                                      .toUnsigned(16)
                                      .toRadixString(16)
                                      .toUpperCase()
                                      .padLeft(4, '0');
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    actions: <Widget>[
                      TextButton(
                        child: const Text('OK'),
                        onPressed: (hexController.text == '' ||
                                decController.text == '')
                            ? null
                            : () {
                                setState(() {
                                  register[regAddress] =
                                      int.parse(decController.text);
                                  Navigator.of(context).pop();
                                });
                              },
                      ),
                    ],
                  );
                });
              },
            );
          },
          cells: [
            DataCell(
              Text(
                text,
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 17,
                ),
              ),
            ),
            DataCell(
              Text(
                'x$hex',
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 17,
                ),
              ),
            ),
            DataCell(
              Text(
                value!.toSigned(16).toString(),
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 17,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  DataTable instructionsTable() {
    return DataTable(
      showCheckboxColumn: false,
      columnSpacing: 100.0,
      dataRowHeight: 25.0,
      dataTextStyle: const TextStyle(
        fontFamily: 'Consolas',
        fontSize: 20,
        color: Colors.black,
      ),
      headingRowHeight: 0,
      columns: [
        DataColumn(label: Container(width: 55.0)),
        DataColumn(label: Container()),
        DataColumn(label: Container()),
        DataColumn(label: Container()),
        DataColumn(label: Container()),
      ],
      rows: List.generate(
        instructions.length,
        (i) {
          var address = instructions[i][0];
          var bits = instructions[i][1];
          var hex = instructions[i][2];

          return DataRow(
              color: (int.parse(address, radix: 16) ==
                      register[RegisterAddress.R_PC])
                  ? MaterialStateColor.resolveWith(
                      (states) => Colors.blue.shade100)
                  : null,
              cells: [
                DataCell(
                  Text(
                    'x$address',
                  ),
                ),
                DataCell(
                  Text(bits),
                ),
                DataCell(
                  Text(
                    'x$hex',
                  ),
                ),
                DataCell(
                  Text(
                    '${instructions[i][3]}',
                  ),
                ),
                DataCell(
                  Text(
                    '${instructions[i][4]}',
                  ),
                ),
              ],
              onSelectChanged: (selected) {
                instructInfo(address, hex, bits, i);
              });
        },
      ),
    );
  }

  Future<void> instructInfo([address, hex, bits, int? i]) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        var addressController = TextEditingController(text: address);
        var hexController = TextEditingController(text: hex);
        var bitController = TextEditingController(text: bits);

        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Instruction info'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 20,
                    ),
                    readOnly: true,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-fA-F0-9]')),
                    ],
                    controller: addressController,
                    decoration: const InputDecoration(
                      border: UnderlineInputBorder(),
                      labelText: 'Location',
                      counterText: '',
                    ),
                    onChanged: (value) => {},
                  ),
                  TextField(
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 20,
                    ),
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-fA-F0-9]')),
                    ],
                    controller: hexController,
                    decoration: const InputDecoration(
                      border: UnderlineInputBorder(),
                      labelText: 'Hexadecimal value',
                      counterText: '',
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        if (value != '') {
                          bitController.text =
                              int.parse(value, radix: 16).toRadixString(2);
                        }
                      });
                    },
                  ),
                  TextField(
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 20,
                    ),
                    maxLength: 16,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-1]')),
                    ],
                    controller: bitController,
                    decoration: const InputDecoration(
                      border: UnderlineInputBorder(),
                      labelText: 'Binary value',
                      counterText: '',
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        if (value != '') {
                          hexController.text =
                              int.parse(value, radix: 2).toRadixString(16);
                        }
                      });
                    },
                    onEditingComplete: () {
                      setDialogState(() {
                        bitController.text =
                            bitController.text.padLeft(16, '0');
                      });
                    },
                  ),
                  Text(
                    (hexController.text == '' || bitController.text == '')
                        ? ''
                        : disassembler.instructionDetails(
                                bitController.text.padLeft(16, '0'),
                                start,
                                -(start -
                                    int.parse(addressController.text,
                                        radix: 16)))[3] +
                            ' ' +
                            disassembler.instructionDetails(
                                bitController.text.padLeft(16, '0'),
                                start,
                                -(start -
                                    int.parse(addressController.text,
                                        radix: 16)))[4],
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: (hexController.text == '' ||
                        bitController.text == '')
                    ? null
                    : () {
                        setState(() {
                          mem_write(
                              int.parse(addressController.text, radix: 16),
                              int.parse(hexController.text, radix: 16));
                          instructions[i!] = disassembler.instructionDetails(
                              bitController.text.padLeft(16, '0'), start, i);
                          Navigator.of(context).pop();
                        });
                      },
              ),
            ],
          );
        });
      },
    );
  }

  var addressField = TextEditingController();
  var hexField = TextEditingController();
  var decField = TextEditingController();
  var binField = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: fileNameController,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Click here to change file name (avoid ".")',
              hintStyle: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (BuildContext context) {
                  return StatefulBuilder(builder: (context, setDialogState) {
                    return AlertDialog(
                      title: const Text('About'),
                      content: SingleChildScrollView(
                        child: Column(
                          children: const [
                            Text('Designed by Link from HCMUT.')
                          ],
                        ),
                      ),
                      actions: <Widget>[
                        TextButton(
                          child: const Text('OK'),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    );
                  });
                },
              );
            },
            icon: const Icon(
              Icons.info_outline,
            ),
          )
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Expanded(
                    flex: 8,
                    child: CodeField(
                      background: Theme.of(context).scaffoldBackgroundColor,
                      controller: codeFieldController,
                      lineNumberStyle: const LineNumberStyle(
                          textStyle: TextStyle(
                        fontFamily: 'DOS',
                        fontSize: 20,
                        color: Colors.black38,
                      )),
                      cursorColor: Colors.black26,
                      // keyboardType: TextInputType.multiline,
                      textStyle: const TextStyle(
                        fontFamily: 'DOS',
                        fontSize: 20,
                        color: Colors.black87,
                      ),
                      minLines: null,
                      maxLines: null,
                      expands: true,
                    ),
                  ),
                  const SizedBox(
                    height: 10.0,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        // Open .asm Button
                        onPressed: () async {
                          FilePickerResult? result =
                              await FilePicker.platform.pickFiles();

                          if (result != null && result.files.isNotEmpty) {
                            final bytes = result.files.single.bytes;
                            final fileName = result.files.single.name;
                            codeFieldController.text = utf8.decode(bytes!);
                            fileNameController.text = fileName.split('.')[0];
                          } else {}
                        },
                        child: Row(
                          children: const [
                            Icon(
                              Icons.folder_open,
                            ),
                            Text('.asm'),
                          ],
                        ),
                      ),
                      const SizedBox(
                        width: 16.0,
                      ),
                      ElevatedButton(
                        // Download .asm Button
                        onPressed: () {
                          html.AnchorElement()
                            ..href =
                                '${Uri.dataFromString(codeFieldController.rawText, mimeType: 'text/plain', encoding: utf8)}'
                            ..download =
                                '${(fileNameController.text == '') ? "Untitled" : fileNameController.text}.asm'
                            ..style.display = 'none'
                            ..click();
                        },
                        child: Row(
                          children: const [
                            Icon(
                              Icons.save,
                            ),
                            Text('.asm'),
                          ],
                        ),
                      ),
                      const SizedBox(
                        width: 16.0,
                      ),
                      ElevatedButton(
                        // Download .obj Button
                        onPressed: () =>
                            FlutterClipboard.copy(codeFieldController.rawText),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.copy,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        // Compile Button
                        onPressed: () {
                          initMachine();
                          compile();
                        },
                        child: Row(
                          children: const [
                            Icon(
                              Icons.arrow_forward,
                            ),
                            Text(
                              'Compile',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: TextField(
                        controller: logController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Log...',
                        ),
                        style: const TextStyle(
                          fontFamily: 'Consola',
                          fontSize: 20,
                        ),
                        textAlignVertical: TextAlignVertical.top,
                        minLines: null,
                        maxLines: null,
                        expands: true,
                        readOnly: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 16.0, 8.0, 8.0),
              child: Column(
                children: [
                  Expanded(
                    flex: 11,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: instructionsTable(),
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 10.0,
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Address value:',
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 20,
                          ),
                        ),
                        SizedBox(
                          width: 75,
                          child: TextField(
                            textAlign: TextAlign.center,
                            maxLength: 4,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[a-fA-F0-9]')),
                            ],
                            controller: addressField,
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 20,
                            ),
                            decoration: const InputDecoration(
                                counterText: '',
                                hintText: 'Address',
                                hintStyle: TextStyle(fontSize: 17)),
                            onChanged: (value) => setState(() {}),
                          ),
                        ),
                        Text(
                          (addressField.text != '')
                              ? mem_read(
                                      int.parse(addressField.text, radix: 16))
                                  .toRadixString(2)
                                  .padLeft(16, '0')
                              : '0000000000000000',
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 20,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          (addressField.text != '')
                              ? 'x' +
                                  mem_read(int.parse(addressField.text,
                                          radix: 16))
                                      .toRadixString(16)
                                      .padLeft(4, '0')
                                      .toUpperCase()
                              : 'x0000',
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 20,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(
                          width: 100.0,
                          child: Text(
                            (addressField.text != '')
                                ? mem_read(
                                        int.parse(addressField.text, radix: 16))
                                    .toSigned(16)
                                    .toString()
                                : '0',
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 20,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            (addressField.text != '')
                                ? disassembler.instructionDetails(
                                    mem_read(int.parse(addressField.text,
                                            radix: 16))
                                        .toRadixString(2)
                                        .padLeft(16, '0'),
                                    start,
                                    register[RegisterAddress.R_PC]! - start)[3]
                                : '',
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 20,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: Text(
                            (addressField.text != '')
                                ? disassembler.instructionDetails(
                                    mem_read(int.parse(addressField.text,
                                            radix: 16))
                                        .toRadixString(2)
                                        .padLeft(16, '0'),
                                    start,
                                    register[RegisterAddress.R_PC]! - start)[4]
                                : '',
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Converter:  ',
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 20,
                          ),
                        ),
                        SizedBox(
                          width: 75,
                          child: TextField(
                            textAlign: TextAlign.center,
                            maxLength: 4,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[a-fA-F0-9]')),
                            ],
                            controller: hexField,
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 20,
                            ),
                            decoration: const InputDecoration(
                              counterText: '',
                              hintText: 'Hex',
                            ),
                            onChanged: (value) => setState(() {
                              if (value == '') {
                                decField.text = '';
                                binField.text = '';
                              } else {
                                decField.text = int.parse(value, radix: 16)
                                    .toSigned(16)
                                    .toString();
                                binField.text = int.parse(value, radix: 16)
                                    .toRadixString(2)
                                    .padLeft(16, '0');
                              }
                            }),
                          ),
                        ),
                        SizedBox(
                          width: 75,
                          child: TextField(
                            textAlign: TextAlign.center,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[-0-9]')),
                            ],
                            controller: decField,
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 20,
                            ),
                            decoration: const InputDecoration(
                              counterText: '',
                              hintText: 'Dec',
                            ),
                            onChanged: (value) => setState(() {
                              if (value == '' || value == '-') {
                                hexField.text = '';
                                binField.text = '';
                              } else if (int.parse(value) > 32767) {
                                decField.text = '32767';
                                hexField.text = '7FFF';
                                binField.text = '0111111111111111';
                              } else if (int.parse(value) < -32768) {
                                decField.text = '-32768';
                                hexField.text = '8000';
                                binField.text = '1000000000000000';
                              } else {
                                hexField.text = int.parse(value)
                                    .toUnsigned(16)
                                    .toRadixString(16)
                                    .toUpperCase()
                                    .padLeft(4, '0');
                                binField.text = int.parse(value, radix: 16)
                                    .toRadixString(2)
                                    .padLeft(16, '0');
                              }
                            }),
                          ),
                        ),
                        SizedBox(
                          width: 200,
                          child: TextField(
                            textAlign: TextAlign.center,
                            maxLength: 16,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-1]')),
                            ],
                            controller: binField,
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 20,
                            ),
                            decoration: const InputDecoration(
                              counterText: '',
                              hintText: 'Bin',
                            ),
                            onChanged: (value) => setState(() {
                              if (value == '') {
                                decField.text = '';
                                hexField.text = '';
                              } else {
                                decField.text = int.parse(value, radix: 2)
                                    .toSigned(16)
                                    .toString();
                                hexField.text = int.parse(value, radix: 2)
                                    .toRadixString(16)
                                    .padLeft(4, '0');
                              }
                            }),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            (binField.text.length < 16)
                                ? ''
                                : disassembler.instructionDetails(
                                    binField.text, start)[3],
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 20,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 150,
                          child: Text(
                            (binField.text.length < 16)
                                ? ''
                                : disassembler.instructionDetails(
                                    binField.text, start)[4],
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 8,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        // Decompile Button
                        onPressed: (instructions.isEmpty)
                            ? null
                            : () {
                                var pc = start;
                                codeFieldController.text =
                                    '.ORIG x${pc.toRadixString(16).toUpperCase()}\n';
                                for (var i = 0; i < instructions.length; i++) {
                                  pc++;
                                  var opcode = instructions[i][3];
                                  var detail = instructions[i][4];

                                  if (opcode != 'NOP' && opcode != 'TRAP') {
                                    codeFieldController.text += opcode + ' ';
                                  }

                                  if (opcode == 'LD' ||
                                      opcode == 'LDI' ||
                                      opcode == 'ST' ||
                                      opcode == 'STI' ||
                                      opcode == 'LEA') {
                                    var details = detail.split(' ');
                                    var PCoffset = int.parse(
                                            details[1].substring(1),
                                            radix: 16) -
                                        pc;

                                    codeFieldController.text +=
                                        '${details[0]} #${PCoffset.toString()}';
                                  } else if (opcode.substring(0, 2) == 'BR') {
                                    var PCoffset = int.parse(
                                            detail.substring(1),
                                            radix: 16) -
                                        pc;

                                    codeFieldController.text +=
                                        '#${PCoffset.toString()}';
                                  } else if (opcode == 'TRAP') {
                                    switch (detail) {
                                      case 'GETC':
                                        codeFieldController.text += 'TRAP x20';
                                        break;
                                      case 'OUT':
                                        codeFieldController.text += 'TRAP x21';
                                        break;
                                      case 'PUTS':
                                        codeFieldController.text += 'TRAP x22';
                                        break;
                                      case 'IN':
                                        codeFieldController.text += 'TRAP x23';
                                        break;
                                      case 'PUTSP':
                                        codeFieldController.text += 'TRAP x24';
                                        break;
                                      case 'HALT':
                                        codeFieldController.text += 'TRAP x25';
                                        break;
                                      default:
                                        codeFieldController.text +=
                                            '.FILL #${int.parse(instructions[i][2], radix: 16)} ; .FILL x${instructions[i][2]}';
                                        break;
                                    }
                                  } else if (opcode == 'NOP') {
                                    codeFieldController.text +=
                                        '.FILL #${int.parse(instructions[i][2], radix: 16)} ; .FILL x${instructions[i][2]}';
                                  } else if (opcode == 'JSR') {
                                    var PCoffset = int.parse(
                                            detail.substring(1),
                                            radix: 16) -
                                        pc;

                                    codeFieldController.text +=
                                        '#${PCoffset.toString()}';
                                  } else {
                                    codeFieldController.text += detail;
                                  }
                                  codeFieldController.text += ' \n';
                                }
                                codeFieldController.text += '.end';
                              },
                        child: Row(
                          children: const [
                            Icon(
                              Icons.arrow_back,
                            ),
                            Text(
                              'Decompile',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        width: 16.0,
                      ),
                      ElevatedButton(
                        // Reset Button
                        onPressed: () {
                          consoleController.text = '';
                          initMachine();
                        },
                        child: Row(
                          children: const [
                            Icon(Icons.restart_alt),
                            Text(
                              'Reinitialize',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        width: 16.0,
                      ),
                      ElevatedButton(
                        // Step Button
                        onPressed: (compiled == false ||
                                register[RegisterAddress.R_PC]! > end ||
                                register[RegisterAddress.R_PC]! < 0x2FFF)
                            ? null
                            : () {
                                stepping = true;
                                stepNext();
                              },
                        child: Row(
                          children: const [
                            Icon(Icons.navigate_next),
                            Text(
                              'Step',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        width: 16.0,
                      ),
                      ElevatedButton(
                        // Run Button
                        onPressed: (compiled == false)
                            ? null
                            : () {
                                stepping = false;
                                run();
                              },
                        child: Row(
                          children: const [
                            Icon(Icons.play_arrow),
                            Text(
                              'Run',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(
                        width: 16.0,
                      ),
                      const Spacer(),
                      ElevatedButton(
                        // Open .obj Button
                        onPressed: () async {
                          FilePickerResult? result =
                              await FilePicker.platform.pickFiles();

                          if (result != null && result.files.isNotEmpty) {
                            setState(() {
                              final bytes = result.files.single.bytes;
                              final fileName = result.files.single.name;
                              obj = Uint8List.fromList(bytes!);
                              start = int.parse(
                                  obj[0].toRadixString(16).padLeft(2, '0') +
                                      obj[1].toRadixString(16).padLeft(2, '0'),
                                  radix: 16);
                              end = (start + (obj.length / 2) - 1) as int;

                              read_obj(obj);
                              instructions =
                                  disassembler.disassembleByMem(start, end);
                              fileNameController.text = fileName.split('.')[0];
                            });
                          } else {}
                        },
                        child: Row(
                          children: const [
                            Icon(
                              Icons.folder_open,
                            ),
                            Text('.obj'),
                          ],
                        ),
                      ),
                      const SizedBox(
                        width: 16.0,
                      ),
                      ElevatedButton(
                        // Download .obj Button
                        onPressed: (instructions.isEmpty)
                            ? null
                            : () {
                                html.AnchorElement()
                                  ..href = '${Uri.dataFromBytes(
                                    disassembler.toBytes(start, end),
                                    mimeType: 'text/plain',
                                  )}'
                                  ..download =
                                      '${(fileNameController.text == '') ? "Untitled" : fileNameController.text}.obj'
                                  ..style.display = 'none'
                                  ..click();
                              },
                        child: Row(
                          children: const [
                            Icon(
                              Icons.save,
                            ),
                            Text('.obj'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 10,
                          child: Column(
                            children: [
                              Expanded(
                                // Console
                                flex: 2,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8.0),
                                  child: TextField(
                                    controller: consoleController,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      hintText: 'Console...',
                                    ),
                                    style: const TextStyle(
                                      fontFamily: 'Consola',
                                      fontSize: 20,
                                    ),
                                    textAlignVertical: TextAlignVertical.top,
                                    // enabled: false,
                                    minLines: null,
                                    maxLines: null,
                                    expands: true,
                                    readOnly: true,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 8,
                                      child: TextField(
                                        maxLength: 1,
                                        controller: inputController,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: TextButton(
                                        onPressed: () {
                                          if (TrapConverter.from(mem_read(
                                                          register[
                                                              RegisterAddress
                                                                  .R_PC]!) &
                                                      0xFF) ==
                                                  Trap.TRAP_IN ||
                                              TrapConverter.from(mem_read(
                                                          register[
                                                              RegisterAddress
                                                                  .R_PC]!) &
                                                      0xFF) ==
                                                  Trap.TRAP_GETC) {
                                            isRunning = true;
                                            stepping ? stepNext() : run();
                                          }

                                          inputController.text = '';
                                        },
                                        child: const Text(
                                          'Send',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: 8.0,
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: memRegisters(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 16.0,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
