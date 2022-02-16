import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:js' as js;
import 'vm.dart';
import 'disassemble.dart' as disassembler;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
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
  TextEditingController codeFieldController = TextEditingController();
  TextEditingController consoleController = TextEditingController();
  TextEditingController inputController = TextEditingController();
  TextEditingController logController = TextEditingController();

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
    });
  }

  var isRunning = false;
  var compiled = false;

  var obj;
  var start, end = 0;

  void compile() {
    setState(() {
      compiled = false;
      logController.text = '';

      var input = codeFieldController.text;
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
        logController.text = 'Compiled';
        instructions = disassembler.disassembleByObj(obj);

        start = int.parse(instructions[0][0], radix: 16);
        end = int.parse(instructions[instructions.length - 1][0], radix: 16);
        // print(end);

        read_obj(obj);

        compiled = true;
      }
    });
  }

  void stepNext() {
    setState(() {
      if (obj == null) read_obj(obj);
      var pc = register[RegisterAddress.R_PC]!;
      var instr = mem_read(pc);
      var op = Opcode.values[instr >> 12];
      var trap = TrapConverter.from(instr & 0xFF);

      var nextInstr = mem_read(pc + 1);
      var nextOp = Opcode.values[nextInstr >> 12];
      var nextTrap = TrapConverter.from(nextInstr & 0xFF);
      if ((op == Opcode.OP_TRAP && trap == Trap.TRAP_HALT)) {
        isRunning = false;
      } else if (pc >= end) {
        isRunning = false;
        logController.text += '\n "TRAP x25" (HALT) should be added.';
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
    read_obj(obj);
    consoleController.text = '';
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
        hex = value.toRadixString(16).padLeft(4, '0').toUpperCase();
        return DataRow(
          onSelectChanged: (selected) {
            var hexController = TextEditingController(text: hex);
            var decController = TextEditingController(text: value.toString());

            showDialog<void>(
              context: context,
              barrierDismissible: false, // user must tap button!
              builder: (BuildContext context) {
                return AlertDialog(
                  title: Text('Change value of $text'),
                  content: SingleChildScrollView(
                    child: Column(
                      children: [
                        TextField(
                          maxLength: 4,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[a-fA-F0-9]')),
                          ],
                          controller: hexController,
                          decoration: const InputDecoration(
                            border: UnderlineInputBorder(),
                            labelText: 'Hexadecimal value',
                          ),
                          onChanged: (value) => {
                            if (value != '')
                              decController.text =
                                  int.parse(value, radix: 16).toString()
                          },
                        ),
                        TextField(
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                          ],
                          controller: decController,
                          decoration: const InputDecoration(
                            border: UnderlineInputBorder(),
                            labelText: 'Decimal value',
                          ),
                          onChanged: (value) {
                            if (int.parse(value) > 65535) {
                              decController.text = 65535.toString();
                              hexController.text = 'FFFF';
                            } else if (value != '') {
                              hexController.text =
                                  int.parse(value).toRadixString(16);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: <Widget>[
                    TextButton(
                      child: const Text('OK'),
                      onPressed: () {
                        setState(() {
                          register[regAddress] = int.parse(decController.text);
                          Navigator.of(context).pop();
                        });
                      },
                    ),
                  ],
                );
              },
            );
          },
          cells: [
            DataCell(
              Text(
                text,
                style: const TextStyle(
                  fontFamily: 'Consola',
                  fontSize: 17,
                ),
              ),
            ),
            DataCell(
              Text(
                'x$hex',
                style: const TextStyle(
                  fontFamily: 'Consola',
                  fontSize: 17,
                ),
              ),
            ),
            DataCell(
              Text(
                value!.toString(),
                style: const TextStyle(
                  fontFamily: 'Consola',
                  fontSize: 17,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
                    child: TextField(
                      controller: codeFieldController,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                        fontFamily: 'DOS',
                        fontSize: 20,
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
                        // Reset Button
                        onPressed: () {
                          initMachine();
                        },
                        child: const Icon(Icons.restart_alt),
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
                                stepNext();
                              },
                        child: const Icon(Icons.arrow_forward),
                      ),
                      const SizedBox(
                        width: 16.0,
                      ),
                      ElevatedButton(
                        // Run Button
                        onPressed: (compiled == false) ? null : () => run(),
                        child: const Icon(Icons.play_arrow),
                      ),
                      const SizedBox(
                        width: 16.0,
                      ),
                      ElevatedButton(
                        // Compile Button
                        onPressed: () {
                          compile();
                        },
                        child: const Icon(
                          Icons.check,
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    flex: 2,
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
                    flex: 7,
                    child: SingleChildScrollView(
                      child: Table(
                        children: List.generate(instructions.length, (i) {
                          return TableRow(
                            children: [
                              Text(
                                'x${instructions[i][0]}',
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 20,
                                ),
                              ),
                              Text(
                                '${instructions[i][1]}',
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 20,
                                ),
                              ),
                              Text(
                                'x${instructions[i][2]}',
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 20,
                                ),
                              ),
                              Text(
                                '${instructions[i][3]}',
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 20,
                                ),
                              ),
                              Text(
                                '${instructions[i][4]}',
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 20,
                                ),
                              )
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 10.0,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const SizedBox(
                        width: 16.0,
                      ),
                      ElevatedButton(
                        // Add Button
                        onPressed: null,
                        child: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 9,
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
                                          isRunning = true;
                                          run();
                                          inputController.text = '';
                                        },
                                        child: const Text(
                                          'OK',
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
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: 8.0,
                            ),
                            child: memRegisters(),
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
