import flet as ft
import pandas as pd
import datetime
import calendar
import os
import re

class MobileScheduleApp:
    def __init__(self, page: ft.Page, file_path: str):
        self.page = page
        self.file_path = file_path
        
        # Настройки мобильной страницы
        self.page.title = "Расписание ТБ-1932"
        self.page.theme_mode = ft.ThemeMode.DARK
        self.page.bgcolor = "#080808"
        self.page.padding = 0
        
        self.schedule_data = {} 
        # 1. УСТАНАВЛИВАЕМ ТЕКУЩУЮ ДАТУ ПРИ ЗАПУСКЕ
        self.current_view_date = datetime.date.today()
        
        self.type_map = {
            r'\(Лек\)': 'Лекция', r'\(Пр\)': 'Практика',
            r'\(Сем\)': 'Семинар', r'\(Лаб\)': 'Лаб'
        }

        # Элементы интерфейса
        self.month_label = ft.Text("", size=16, color="#4ec9b0", weight="bold", text_align=ft.TextAlign.CENTER, expand=True)
        self.schedule_list = ft.ListView(expand=True, spacing=0, padding=10)

        self.build_ui()
        self.load_data()
        self.update_view()

    def clean_full_type(self, text):
        if not text or str(text).lower() == "nan": return None
        t = str(text).replace('\n', ' ').strip()
        
        # Убираем асинхронные занятия по требованию
        if re.search(r'асинх', t, flags=re.IGNORECASE): return None

        found_type = ""
        for pattern, full_name in self.type_map.items():
            if re.search(pattern, t, flags=re.IGNORECASE):
                t = re.sub(pattern, '', t, flags=re.IGNORECASE)
                found_type = full_name
                break
                
        t = re.sub(r'[А-Я][а-яё]+\s+[А-Я]\.\s+[А-Я]\.?', '', t)
        t = re.sub(r'\d{1,3}-\d[А-Я]*|кк\d{3}|ЦФК|СпортЗал|ЭИОС|каф\.|НОЦ|ФМНиИТ', '', t, flags=re.IGNORECASE)
        t = re.sub(r'\s+', ' ', t).strip()
        return f"{t} — {found_type}" if found_type else t

    def load_data(self):
        if not os.path.exists(self.file_path):
            self.schedule_list.controls.append(ft.Text("Файл расписания не найден", color="red", size=14))
            return
            
        try:
            df = pd.read_excel(self.file_path, sheet_name=2, header=None)
            h_idx = next(i for i, r in df.iterrows() if any("1932" in str(x) for x in r))
            headers = [str(c).strip() for c in df.iloc[h_idx]]
            data = df.iloc[h_idx + 1:].copy()
            date_cols = [i for i, h in enumerate(headers) if "Дата" in h]

            for dc in date_cols:
                data.iloc[:, dc] = data.iloc[:, dc].ffill()
                t_col = dc + 1
                
                idx_32 = next((j for j in range(dc+1, len(headers)) if "1932" in headers[j]), None)
                idx_31 = next((j for j in range(dc+1, len(headers)) if "1931" in headers[j]), None)

                for _, row in data.iterrows():
                    m = re.search(r'(\d{2}\.\d{2}\.\d{2,4})', str(row.iloc[dc]))
                    if not m: continue
                    
                    d_obj = datetime.datetime.strptime(m.group(1), "%d.%m.%y" if len(m.group(1))<9 else "%d.%m.%Y").date()
                    
                    v32 = str(row.iloc[idx_32]).strip() if idx_32 is not None else ""
                    v31 = str(row.iloc[idx_31]).strip() if idx_31 is not None else ""
                    
                    # Приоритет группе ТБ-1932
                    content = v32 if v32 and v32.lower() != "nan" else (v31 if "(Лек)" in v31 else "")
                    
                    if content:
                        cleaned = self.clean_full_type(content)
                        if cleaned:
                            day_list = self.schedule_data.setdefault(d_obj, [])
                            time = str(row.iloc[t_col]).split('-')[0].strip()
                            if (time, cleaned) not in day_list: day_list.append((time, cleaned))
        except Exception as e:
            self.schedule_list.controls.append(ft.Text(f"Ошибка чтения: {str(e)}", color="red", size=14))

    def prev_month(self, e):
        self.current_view_date = (self.current_view_date.replace(day=1) - datetime.timedelta(days=1))
        self.update_view()

    def next_month(self, e):
        self.current_view_date = (self.current_view_date.replace(day=28) + datetime.timedelta(days=5)).replace(day=1)
        self.update_view()

    def build_ui(self):
        nav_row = ft.Container(
            content=ft.Row(
                controls=[
                    ft.IconButton(icon=ft.Icons.ARROW_BACK, on_click=self.prev_month, icon_color="white", icon_size=16),
                    self.month_label,
                    ft.IconButton(icon=ft.Icons.ARROW_FORWARD, on_click=self.next_month, icon_color="white", icon_size=16),
                ],
                alignment=ft.MainAxisAlignment.SPACE_BETWEEN
            ),
            bgcolor="#222222",
            padding=10
        )
        self.page.add(nav_row, self.schedule_list)

    def update_view(self):
        self.schedule_list.controls.clear()
        today = datetime.date.today()
        
        months_ru = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
        self.month_label.value = f"{months_ru[self.current_view_date.month - 1]} {self.current_view_date.year}"
        
        cal = calendar.Calendar(0).monthdatescalendar(self.current_view_date.year, self.current_view_date.month)

        days_added = 0
        for week in cal:
            for day in week:
                # Фильтруем дни текущего месяца и исключаем воскресенья
                if day.month != self.current_view_date.month or day.weekday() == 6: 
                    continue 
                
                # 2. СКРЫВАЕМ ПРОШЕДШИЕ ДНИ
                if day < today:
                    continue

                if day in self.schedule_data:
                    days_added += 1
                    day_name = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ"][day.weekday()]
                    is_today = (day == today)
                    
                    bg_color = "#1a2622" if is_today else "#111111"
                    border_color = "#4ec9b0" if is_today else "#333333"
                    date_color = "#4ec9b0" if is_today else "#569cd6"
                    
                    subjects_ui = []
                    for time, subj in sorted(self.schedule_data[day], key=lambda x: x[0]):
                        subjects_ui.append(
                            ft.Text(f"• {time}  {subj}", color="#dcdcaa", size=14)
                        )

                    day_card = ft.Container(
                        bgcolor=bg_color,
                        border=ft.Border.all(1, border_color),
                        border_radius=8,
                        padding=15,
                        margin=ft.Margin.only(bottom=10),
                        expand=True,
                        content=ft.Column(
                            controls=[
                                ft.Text(f"{day.day:02d}.{day.month:02d} - {day_name}", color=date_color, size=16, weight="bold"),
                                *subjects_ui
                            ],
                            spacing=6
                        )
                    )
                    self.schedule_list.controls.append(day_card)
                    
        if days_added == 0:
            self.schedule_list.controls.append(
                ft.Text("Актуальных пар в этом месяце нет", color="#888888", size=16, text_align=ft.TextAlign.CENTER)
            )

        self.page.update()

def main(page: ft.Page):
    file_path = "Расписание_бакалавриат_БТ_весенний_семестр_1.xlsx"
    app = MobileScheduleApp(page, file_path)

if __name__ == "__main__":
    ft.run(main)