import 'dart:typed_data';

import 'package:lc3/vm.dart';

List disassembleByObj(obj) {
  var instructionsBits = <String>[];
  var instructions = List.empty(growable: true);

  for (var i = 2; i < obj.length; i += 2) {
    instructionsBits.add(obj[i].toRadixString(2).padLeft(8, '0') +
        obj[i + 1].toRadixString(2).padLeft(8, '0'));
  }
  var orig = int.parse(
      obj[0].toRadixString(16).padLeft(2, '0') +
          obj[1].toRadixString(16).padLeft(2, '0'),
      radix: 16);

  for (var i = 0; i < instructionsBits.length; i++) {
    instructions.add(instructionDetails(instructionsBits[i], orig, i));
  }

  return instructions;
}

List disassembleByMem(start, end, nop) {
  var instructionsBits = <String>[];
  var instructions = List.empty(growable: true);

  for (var i = start; i < end; i++) {
    instructionsBits.add(mem_read(i).toRadixString(2).padLeft(16, '0'));
  }
  for (var i = 0; i < instructionsBits.length; i++) {
    if (nop == true) {
      instructions.add(instructionDetails(instructionsBits[i], start, i));
    } else {
      if (instructionsBits[i] != '0000000000000000') {
        instructions.add(instructionDetails(instructionsBits[i], start, i));
      }
    }
  }

  return instructions;
}

Uint8List toBytes(start, end) {
  var instructionsBits = <String>[];
  var bytes = List<int>.empty(growable: true);

  for (var i = start; i < end; i++) {
    instructionsBits.add(mem_read(i).toRadixString(2).padLeft(16, '0'));
  }
  var startBit = start.toRadixString(2).padLeft(16, '0');
  bytes.add(int.parse(startBit.substring(0, 8), radix: 2));
  bytes.add(int.parse(startBit.substring(8), radix: 2));
  for (var i = 0; i < instructionsBits.length; i++) {
    bytes.add(int.parse(instructionsBits[i].substring(0, 8), radix: 2));
    bytes.add(int.parse(instructionsBits[i].substring(8), radix: 2));
  }

  return Uint8List.fromList(bytes);
}

List<String> instructionDetails(String instructionBits, int orig,
    [int? currentInst]) {
  int current = 0;
  if (currentInst != null) current = currentInst;
  var PC = (orig + current).toRadixString(16);
  var opcode, details = '';
  var hex =
      int.parse(instructionBits, radix: 2).toRadixString(16).padLeft(4, '0');

  var opcodeBits = instructionBits.substring(0, 4);

  switch (opcodeBits) {
    case '0001': // ADD
      {
        var DR = instructionBits.substring(4, 7);
        var SR1 = instructionBits.substring(7, 10);
        var SR2 = '';
        if (instructionBits[10] == '0') {
          SR2 = 'R${int.parse(instructionBits.substring(13), radix: 2)}';
        } else {
          SR2 =
              '#${int.parse(instructionBits.substring(11), radix: 2).toSigned(5).toString()}';
        }
        opcode = 'ADD';
        details =
            'R${int.parse(DR, radix: 2)}, R${int.parse(SR1, radix: 2)}, $SR2';
      }
      break;

    case '0101': // AND
      {
        var DR = instructionBits.substring(4, 7);
        var SR1 = instructionBits.substring(7, 10);
        var SR2 = '';
        if (instructionBits[10] == '0') {
          SR2 = 'R${int.parse(instructionBits.substring(13), radix: 2)}';
        } else {
          SR2 =
              '#${int.parse(instructionBits.substring(11), radix: 2).toSigned(5).toString()}';
        }
        opcode = 'AND';
        details =
            'R${int.parse(DR, radix: 2)}, R${int.parse(SR1, radix: 2)}, $SR2';
      }
      break;

    case '0000': // BR
      {
        var conditionBits = instructionBits.substring(4, 7).padLeft(3, '0');
        var conditions = '';
        if (conditionBits == '000') {
          opcode = 'NOP';
          break;
        } else {
          if (conditionBits[0] == '1') conditions += 'n';
          if (conditionBits[1] == '1') conditions += 'z';
          if (conditionBits[2] == '1') conditions += 'p';
        }

        opcode = 'BR$conditions';
        var pcOffset =
            int.parse(instructionBits.substring(7), radix: 2).toSigned(9);
        if (currentInst != null) {
          var dest = (pcOffset + orig + current + 1).toRadixString(16);
          details = 'x${dest.toUpperCase()}';
        } else {
          details = '#$pcOffset';
        }
      }
      break;

    case '0010': // LD
      {
        var DR = instructionBits.substring(4, 7);

        opcode = 'LD';
        var pcOffset =
            int.parse(instructionBits.substring(7), radix: 2).toSigned(9);
        if (currentInst != null) {
          var dest = (pcOffset + orig + current + 1).toRadixString(16);
          details = 'R${int.parse(DR, radix: 2)}, x${dest.toUpperCase()}';
        } else {
          details = 'R${int.parse(DR, radix: 2)}, #$pcOffset';
        }
      }
      break;
    case '1010': // LDI
      {
        var DR = instructionBits.substring(4, 7);

        opcode = 'LDI';
        var pcOffset =
            int.parse(instructionBits.substring(7), radix: 2).toSigned(9);
        if (currentInst != null) {
          var dest = (pcOffset + orig + current + 1).toRadixString(16);
          details = 'R${int.parse(DR, radix: 2)}, x${dest.toUpperCase()}';
        } else {
          details = 'R${int.parse(DR, radix: 2)}, #$pcOffset';
        }
      }
      break;

    case '0110': // LDR
      {
        var DR = instructionBits.substring(4, 7);
        var baseR = instructionBits.substring(7, 10);
        var offset =
            int.parse(instructionBits.substring(10), radix: 2).toSigned(6);

        opcode = 'LDR';
        details =
            'R${int.parse(DR, radix: 2)}, R${int.parse(baseR, radix: 2)}, #${offset.toString()}';
      }
      break;

    case '1110': // LEA
      {
        var DR = instructionBits.substring(4, 7);

        opcode = 'LEA';
        var pcOffset =
            int.parse(instructionBits.substring(7), radix: 2).toSigned(9);
        if (currentInst != null) {
          var dest = (pcOffset + orig + current + 1).toRadixString(16);
          details = 'R${int.parse(DR, radix: 2)}, x${dest.toUpperCase()}';
        } else {
          details = 'R${int.parse(DR, radix: 2)}, #$pcOffset';
        }
      }
      break;

    case '0011': // ST
      {
        var SR = instructionBits.substring(4, 7);

        opcode = 'ST';
        var pcOffset =
            int.parse(instructionBits.substring(7), radix: 2).toSigned(9);
        if (currentInst != null) {
          var dest = (pcOffset + orig + current + 1).toRadixString(16);
          details = 'R${int.parse(SR, radix: 2)}, x${dest.toUpperCase()}';
        } else {
          details = 'R${int.parse(SR, radix: 2)}, #$pcOffset';
        }
      }
      break;
    case '1011': // STI
      {
        var SR = instructionBits.substring(4, 7);

        opcode = 'STI';
        var pcOffset =
            int.parse(instructionBits.substring(7), radix: 2).toSigned(9);
        if (currentInst != null) {
          var dest = (pcOffset + orig + current + 1).toRadixString(16);
          details = 'R${int.parse(SR, radix: 2)}, x${dest.toUpperCase()}';
        } else {
          details = 'R${int.parse(SR, radix: 2)}, #$pcOffset';
        }
      }
      break;

    case '0111': // STR
      {
        var SR = instructionBits.substring(4, 7);
        var baseR = instructionBits.substring(7, 10);
        var offset =
            int.parse(instructionBits.substring(10), radix: 2).toSigned(6);

        opcode = 'STR';
        details =
            'R${int.parse(SR, radix: 2)}, R${int.parse(baseR, radix: 2)}, #${offset.toString()}';
      }
      break;

    case '1001': // NOT
      {
        var DR = instructionBits.substring(4, 7);
        var SR = instructionBits.substring(7, 10);

        opcode = 'NOT';
        details = 'R${int.parse(DR, radix: 2)}, R${int.parse(SR, radix: 2)}';
      }
      break;

    case '1111': // TRAP
      {
        var trapvect8 = instructionBits.substring(8);
        var traphex = int.parse(trapvect8, radix: 2).toRadixString(16);
        opcode = 'TRAP';

        switch (traphex) {
          case '20':
            details = 'GETC';
            break;

          case '21':
            details = 'OUT';
            break;

          case '22':
            details = 'PUTS';
            break;

          case '23':
            details = 'IN';
            break;

          case '24':
            details = 'PUTSP';
            break;

          case '25':
            details = 'HALT';
            break;

          default:
            details = 'x${traphex.toUpperCase().padLeft(2, '0')}';
            break;
        }
      }
      break;
    case '1100': // JMP, RET
      {
        var baseR = instructionBits.substring(7, 10);
        if (baseR == '111') {
          opcode = 'RET';
        } else {
          opcode = 'JMP';
          details = 'R${int.parse(baseR, radix: 2)}';
        }
      }
      break;

    case '0100': // JSR, JSRR
      {
        if (instructionBits[4] == '1') {
          opcode = 'JSR';
          var pcOffset =
              int.parse(instructionBits.substring(5), radix: 2).toSigned(11);
          if (currentInst != null) {
            details =
                'x${(pcOffset + orig + current + 1).toRadixString(16).toUpperCase()}';
          } else {
            details = '#$pcOffset';
          }
        } else {
          var baseR = instructionBits.substring(7, 10);
          opcode = 'JSRR';
          details = 'R${int.parse(baseR, radix: 2)}';
        }
      }
      break;

    case '1000': // JSR, JSRR
      {
        opcode = 'RTI';
      }
      break;

    default:
      opcode = 'NOP';
      break;
  }
  // print('x$PC $instructionBits x$hex $opcode $details');
  return [
    PC.toUpperCase(),
    instructionBits,
    hex.toUpperCase(),
    opcode.toUpperCase(),
    details
  ];
}
