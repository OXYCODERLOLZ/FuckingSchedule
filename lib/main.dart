import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

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
      title: 'Планировщик ТБ-1932',
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
  String statusMessage = "Загрузка локального файла...";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadLocalExcel();
  }

  Future<void> loadLocalExcel() async {
    try {
      final data = await rootBundle.load('assets/schedule.xlsx');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      var excel = Excel.decodeBytes(bytes);
      
      Map<DateTime, List<List<String>>> parsedData = {};
      Sheet? targetSheet;
      int headerRowIdx = -1;
      List<String> headers = [];

      String getCleanText(Data? cell) {
        if (cell == null || cell.value == null) return "";
        String s = cell.value.toString();
        return s.replaceAll(RegExp(r'^[A-Za-z]+CellValue\(([\s\S]*)\)$'), r'\1').trim();
      }

      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table]!;
        for (int i = 0; i < sheet.maxRows; i++) {
          var row = sheet.row(i);
          bool found = row.any((cell) => cell?.value.toString().contains('1932') ?? false);
          if (found) {
            targetSheet = sheet;
            headerRowIdx = i;
            headers = row.map((c) => getCleanText(c)).toList();
            break;
          }
        }
        if (targetSheet != null) break;
      }

      if (targetSheet == null) {
        setState(() {
          statusMessage = "Группа 1932 не найдена";
          isLoading = false;
        });
        return;
      }

      List<int> dateCols = [];
      for (int i = 0; i < headers.length; i++) {
        if (headers[i].contains('Дата')) dateCols.add(i);
      }

      int idx32 = headers.indexWhere((h) => h.contains('1932'));
      int idx31 = headers.indexWhere((h) => h.contains('1931'));

      String lastDateStr = "";

      for (int r = headerRowIdx + 1; r < targetSheet.maxRows; r++) {
        var row = targetSheet.row(r);
        if (row.isEmpty) continue;

        for (int dc in dateCols) {
          if (dc >= row.length) continue;

          String rawDate = getCleanText(row[dc]);
          if (rawDate.isNotEmpty && rawDate != "null") {
            lastDateStr = rawDate;
          } else {
            rawDate = lastDateStr;
          }

          DateTime? dObj;
          var matchRu = RegExp(r'(\d{2})\.(\d{2})\.(\d{2,4})').firstMatch(rawDate);
          if (matchRu != null) {
            int year = int.parse(matchRu.group(3)!);
            if (year < 100) year += 2000;
            dObj = DateTime(year, int.parse(matchRu.group(2)!), int.parse(matchRu.group(1)!));
          }

          if (dObj == null) continue;

          int tCol = dc + 1;
          if (tCol >= row.length) continue;
          
          String time = getCleanText(row[tCol]).split('-')[0].trim();
          String v32 = (idx32 != -1 && idx32 < row.length) ? getCleanText(row[idx32]) : "";
          String v31 = (idx31 != -1 && idx31 < row.length) ? getCleanText(row[idx31]) : "";

          String content = v32.isNotEmpty && v32.toLowerCase() != "null" ? v32 : (v31.contains("(Лек)") ? v31 : "");

          if (content.isNotEmpty) {
            String? cleaned = cleanType(content);
            if (cleaned != null) {
              DateTime pureDate = DateTime(dObj.year, dObj.month, dObj.day);
              parsedData.putIfAbsent(pureDate, () => []);
              if (!parsedData[pureDate]!.any((e) => e[0] == time && e[1] == cleaned)) {
                parsedData[pureDate]!.add([time, cleaned]);
              }
            }
          }
        }
      }

      setState(() {
        scheduleData = parsedData;
        isLoading = false;
      });

    } catch (e) {
      setState(() {
        statusMessage = "Ошибка файла";
        isLoading = false;
      });
    }
  }

  String? cleanType(String? text) {
    if (text == null || text.trim().isEmpty || text.toLowerCase() == 'nan') return null;
    String t = text.replaceAll('\n', ' ').trim();
    if (t.toLowerCase().contains('асинх')) return null;

    String foundType = "";
    if (t.contains(RegExp(r'\(Лек\)', caseSensitive: false))) foundType = "Лекция";
    if (t.contains(RegExp(r'\(Пр\)', caseSensitive: false))) foundType = "Практика";
    if (t.contains(RegExp(r'\(Сем\)', caseSensitive: false))) foundType = "Семинар";
    if (t.contains(RegExp(r'\(Лаб\)', caseSensitive: false))) foundType = "Лаб";

    t = t.replaceAll(RegExp(r'\((Лек|Пр|Сем|Лаб)\)', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'[А-Я][а-яё]+\s+[А-Я]\.\s+[А-Я]\.?'), ''); 
    t = t.replaceAll(RegExp(r'\d{1,3}-\d[А-Я]*|кк\d{3}|ЦФК|СпортЗал|ЭИОС|каф\.|НОЦ|ФМНиИТ', caseSensitive: false), '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim() + (foundType.isNotEmpty ? " — $foundType" : "");
  }

  void changeMonth(int delta) {
    setState(() {
      currentViewDate = DateTime(currentViewDate.year, currentViewDate.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    List<DateTime> daysInMonth = [];
    
    int daysCount = DateUtils.getDaysInMonth(currentViewDate.year, currentViewDate.month);
    for (int i = 1; i <= daysCount; i++) {
      DateTime d = DateTime(currentViewDate.year, currentViewDate.month, i);
      // Оставляем только фильтр воскресений. Прошедшие дни теперь ПОКАЗЫВАЮТСЯ.
      if (d.weekday == 7) continue;
      if (scheduleData.containsKey(d)) daysInMonth.add(d);
    }

    daysInMonth.sort();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
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
                    style: const TextStyle(color: Color(0xFF4EC9B0), fontSize: 16.0, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                    onPressed: () => changeMonth(1),
                  ),
                ],
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF4EC9B0)))
                  : daysInMonth.isEmpty
                      ? const Center(child: Text("Занятий не найдено", style: TextStyle(color: Colors.grey, fontSize: 16.0)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: daysInMonth.length,
                          itemBuilder: (context, index) {
                            DateTime day = daysInMonth[index];
                            bool isToday = day.isAtSameMomentAs(today);
                            List<List<String>> subjects = scheduleData[day]!;
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
                                      fontSize: 16.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  ...subjects.map((s) => Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text(
                                          "• ${s[0]}  ${s[1]}",
                                          style: const TextStyle(color: Color(0xFFDCDCAA), fontSize: 14.0),
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
