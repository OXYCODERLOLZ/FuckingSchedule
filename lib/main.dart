import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';

const String excelUrl =
    "https://github.com/OXYCODERLOLZ/FuckingSchedule/raw/main/%D0%A0%D0%B0%D1%81%D0%BF%D0%B8%D1%81%D0%B0%D0%BD%D0%B8%D0%B5_%D0%B1%D0%B0%D0%BA%D0%B0%D0%BB%D0%B0%D0%B2%D1%80%D0%B8%D0%B0%D1%82_%D0%91%D0%A2_%D0%B2%D0%B5%D1%81%D0%B5%D0%BD%D0%BD%D0%B8%D0%B9_%D1%81%D0%B5%D0%BC%D0%B5%D1%81%D1%82%D1%80_1.xlsx";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  runApp(const ScheduleApp());
}

class ScheduleApp extends StatelessWidget {
  const ScheduleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Расписание ТБ-1932',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080808),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF222222)),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Map<DateTime, List<List<String>>> scheduleData = {};
  DateTime currentViewDate = DateTime.now();
  String statusMessage = "Синхронизация...";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    syncAndLoad();
  }

  Future<void> syncAndLoad() async {
    setState(() {
      isLoading = true;
      statusMessage = "Загрузка данных...";
    });

    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/cached_schedule.xlsx';
      final file = File(filePath);

      // 1. Попытка скачать свежий файл (ждем максимум 7 секунд)
      try {
        final response = await http.get(Uri.parse(excelUrl)).timeout(const Duration(seconds: 7));
        if (response.statusCode == 200) {
          await file.writeAsBytes(response.bodyBytes);
          print("Файл обновлен с GitHub");
        }
      } catch (e) {
        print("Нет сети, используем локальный кэш: $e");
      }

      // 2. Чтение файла
      if (await file.exists()) {
        await parseExcel(file);
      } else {
        setState(() {
          statusMessage = "Нет данных. Нужен интернет для первого запуска.";
        });
      }
    } catch (e) {
      print("Критическая ошибка: $e");
      setState(() {
        statusMessage = "Ошибка загрузки";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  String? cleanType(String? text) {
    if (text == null || text.trim().isEmpty || text.toLowerCase() == 'nan') return null;
    String t = text.replaceAll('\n', ' ').trim();

    // ЖЕСТКО УБИРАЕМ АСИНХРОННЫЕ
    if (t.toLowerCase().contains('асинх')) return null;

    String foundType = "";
    if (t.contains(RegExp(r'\(Лек\)', caseSensitive: false))) foundType = "Лекция";
    if (t.contains(RegExp(r'\(Пр\)', caseSensitive: false))) foundType = "Практика";
    if (t.contains(RegExp(r'\(Сем\)', caseSensitive: false))) foundType = "Семинар";
    if (t.contains(RegExp(r'\(Лаб\)', caseSensitive: false))) foundType = "Лаб";

    t = t.replaceAll(RegExp(r'\((Лек|Пр|Сем|Лаб)\)', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'[А-Я][а-яё]+\s+[А-Я]\.\s+[А-Я]\.?'), ''); // Преподы
    t = t.replaceAll(RegExp(r'\d{1,3}-\d[А-Я]*|кк\d{3}|ЦФК|СпортЗал|ЭИОС|каф\.|НОЦ|ФМНиИТ', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();

    return foundType.isNotEmpty ? "$t — $foundType" : t;
  }

  Future<void> parseExcel(File file) async {
    var bytes = file.readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);
    Map<DateTime, List<List<String>>> parsedData = {};

    // Ищем таблицу с расписанием
    Sheet? sheet;
    for (var table in excel.tables.keys) {
      sheet = excel.tables[table];
      break; // Берем первый лист
    }

    if (sheet == null) return;

    int headerRowIdx = -1;
    List<String> headers = [];

    // Ищем заголовок по наличию 1932
    for (int i = 0; i < sheet.maxRows; i++) {
      var row = sheet.row(i);
      bool found = row.any((cell) => cell?.value.toString().contains('1932') ?? false);
      if (found) {
        headerRowIdx = i;
        headers = row.map((c) => c?.value.toString().trim() ?? '').toList();
        break;
      }
    }

    if (headerRowIdx == -1) return;

    List<int> dateCols = [];
    for (int i = 0; i < headers.length; i++) {
      if (headers[i].contains('Дата')) dateCols.add(i);
    }

    int idx32 = headers.indexWhere((h) => h.contains('1932'));
    int idx31 = headers.indexWhere((h) => h.contains('1931'));

    String lastDate = "";

    for (int r = headerRowIdx + 1; r < sheet.maxRows; r++) {
      var row = sheet.row(r);
      if (row.isEmpty) continue;

      for (int dc in dateCols) {
        if (dc >= row.length) continue;

        String rawDate = row[dc]?.value.toString().trim() ?? "";
        if (rawDate.isNotEmpty && rawDate != "null") {
          lastDate = rawDate;
        } else {
          rawDate = lastDate;
        }

        var match = RegExp(r'(\d{2}\.\d{2}\.\d{2,4})').firstMatch(rawDate);
        if (match == null) continue;

        String dateStr = match.group(1)!;
        DateTime? dObj;
        try {
          if (dateStr.length <= 8) {
            dObj = DateFormat("dd.MM.yy").parseStrict(dateStr);
          } else {
            dObj = DateFormat("dd.MM.yyyy").parseStrict(dateStr);
          }
        } catch (e) {
          continue;
        }

        int tCol = dc + 1;
        if (tCol >= row.length) continue;
        String rawTime = row[tCol]?.value.toString().trim() ?? "";
        String time = rawTime.split('-')[0].trim();

        String v32 = (idx32 != -1 && idx32 < row.length) ? (row[idx32]?.value.toString().trim() ?? "") : "";
        String v31 = (idx31 != -1 && idx31 < row.length) ? (row[idx31]?.value.toString().trim() ?? "") : "";

        String content = "";
        if (v32.isNotEmpty && v32.toLowerCase() != "null") {
          content = v32;
        } else if (v31.contains("(Лек)")) {
          content = v31;
        }

        if (content.isNotEmpty) {
          String? cleaned = cleanType(content);
          if (cleaned != null) {
            // Нормализуем дату, отбрасывая время
            DateTime pureDate = DateTime(dObj.year, dObj.month, dObj.day);
            parsedData.putIfAbsent(pureDate, () => []);
            // Проверка на дубликаты
            bool exists = parsedData[pureDate]!.any((element) => element[0] == time && element[1] == cleaned);
            if (!exists) {
              parsedData[pureDate]!.add([time, cleaned]);
            }
          }
        }
      }
    }

    setState(() {
      scheduleData = parsedData;
    });
  }

  void changeMonth(int delta) {
    setState(() {
      currentViewDate = DateTime(currentViewDate.year, currentViewDate.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    DateTime today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    List<DateTime> daysInMonth = [];
    
    int daysCount = DateUtils.getDaysInMonth(currentViewDate.year, currentViewDate.month);
    for (int i = 1; i <= daysCount; i++) {
      DateTime d = DateTime(currentViewDate.year, currentViewDate.month, i);
      // Скрываем воскресенья и прошедшие дни
      if (d.weekday == 7 || d.isBefore(today)) continue;
      if (scheduleData.containsKey(d)) daysInMonth.add(d);
    }

    daysInMonth.sort();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Навигация по месяцам
            Container(
              color: const Color(0xFF222222),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    onPressed: () => changeMonth(-1),
                  ),
                  Text(
                    isLoading ? statusMessage : DateFormat.yMMMM('ru_RU').format(currentViewDate).toUpperCase(),
                    style: const TextStyle(color: Color(0xFF4EC9B0), fontSize: 16.0, fontWeight: FontWeight.bold), // Шрифт целое число
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                    onPressed: () => changeMonth(1),
                  ),
                ],
              ),
            ),
            // Список карточек
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF4EC9B0)))
                  : daysInMonth.isEmpty
                      ? const Center(
                          child: Text("Актуальных пар в этом месяце нет",
                              style: TextStyle(color: Color(0xFF888888), fontSize: 16.0)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: daysInMonth.length,
                          itemBuilder: (context, index) {
                            DateTime day = daysInMonth[index];
                            bool isToday = day.isAtSameMomentAs(today);
                            List<List<String>> subjects = scheduleData[day]!;
                            
                            // Сортировка по времени
                            subjects.sort((a, b) => a[0].compareTo(b[0]));

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: isToday ? const Color(0xFF1A2622) : const Color(0xFF111111),
                                border: Border.all(color: isToday ? const Color(0xFF4EC9B0) : const Color(0xFF333333)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('dd.MM - EEEE', 'ru_RU').format(day).toUpperCase(),
                                    style: TextStyle(
                                      color: isToday ? const Color(0xFF4EC9B0) : const Color(0xFF569CD6),
                                      fontSize: 16.0, // Шрифт целое число
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ...subjects.map((s) => Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text(
                                          "• ${s[0]}  ${s[1]}",
                                          style: const TextStyle(color: Color(0xFFDCDCAA), fontSize: 14.0), // Ширина подгоняется автоматически движком
                                        ),
                                      )),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
