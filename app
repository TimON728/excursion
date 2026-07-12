import streamlit as st
import pandas as pd
import sqlite3
import hashlib
import os
from pathlib import Path

DB_PATH = "tourism.db"
UPLOAD_DIR = "uploads"

# Создаем папку для загрузок, если её нет
Path(UPLOAD_DIR).mkdir(exist_ok=True)

st.set_page_config(page_title="Отдых в Лодейнопольском районе", layout="wide")


def get_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_connection() as conn:
        cur = conn.cursor()

        cur.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT UNIQUE NOT NULL,
                nickname TEXT NOT NULL,
                password_hash TEXT NOT NULL
            )
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS reviews (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                excursion_id INTEGER NOT NULL,
                user_email TEXT NOT NULL,
                text TEXT NOT NULL,
                photo_path TEXT, 
                rating INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 5),
                FOREIGN KEY(user_email) REFERENCES users(email)
            )
        """)
        conn.commit()


def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


def register_user(email: str, nickname: str, password: str) -> bool:
    try:
        with get_connection() as conn:
            cur = conn.cursor()
            cur.execute(
                "INSERT INTO users (email, nickname, password_hash) VALUES (?, ?, ?)",
                (email, nickname, hash_password(password))
            )
            conn.commit()
        return True
    except sqlite3.IntegrityError:
        return False


def login_user(email: str, password: str) -> tuple[bool, str | None]:
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute("SELECT password_hash, nickname FROM users WHERE email = ?", (email,))
        row = cur.fetchone()
        if row and row["password_hash"] == hash_password(password):
            return True, row["nickname"]
        return False, None


def get_reviews_for_excursion(excursion_id: int):
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT u.nickname, r.text, r.photo_path, r.rating 
            FROM reviews r
            JOIN users u ON r.user_email = u.email
            WHERE r.excursion_id = ?
        """, (excursion_id,))
        return cur.fetchall()


def get_stats_for_excursion(excursion_id: int):
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute("""
            SELECT AVG(rating) as avg_rating, COUNT(*) as count_reviews 
            FROM reviews WHERE excursion_id = ?
        """, (excursion_id,))
        row = cur.fetchone()
        avg = row["avg_rating"]
        count = row["count_reviews"]
        return (round(avg, 1) if avg else 0.0, count)


def save_uploaded_file(uploaded_file):
    if uploaded_file is None:
        return None

    import time
    safe_name = f"{int(time.time())}_{uploaded_file.name}"
    file_path = os.path.join(UPLOAD_DIR, safe_name)

    with open(file_path, "wb") as f:
        f.write(uploaded_file.getbuffer())

    return safe_name


def add_review(excursion_id: int, user_email: str, text: str, photo_filename: str | None, rating: int):
    with get_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO reviews (excursion_id, user_email, text, photo_path, rating) VALUES (?, ?, ?, ?, ?)",
            (excursion_id, user_email, text, photo_filename, rating)
        )
        conn.commit()


init_db()

# --- БАЗА ДАННЫХ ЭКСКУРСИЙ (Добавлено поле transport) ---
excursions = [
    {"id": 1, "title": "Вепсская культура и быт", "type": "Этнография", "capacity": "Семейная", "duration_days": "2 дня",
     "price": 8500, "guide": "Анна Петровна",
     "description": "Погружение в мир вепсов: мастер-класс по ткачеству, знакомство с обрядами и кухней. Посещение музея под открытым небом.",
     "phone_number": "+7 (800) 555 35 35",
     "route": "Доможирово → Курпово",
     "image_url": "https://этнопетербург.рф/upload/resize_cache/iblock/409/600_450_185d52f3131d7c2e003ca2c902009a118/vepsy1.jpg",
     "transport": "Автобусная"},

    {"id": 2, "title": "Тропы Нижне-Свирского заповедника", "type": "Природа", "capacity": "Индивидуальная",
     "duration_days": '1 день',
     "price": 6000, "guide": "Игорь Семёнович",
     "description": "Прогулка по деревянным настилам над болотами. Наблюдение за птицами, поиск следов диких животных. Эко-тропа средней сложности.",
     "phone_number": "+7 (921) 553 21 09", "route": "Доможирово → Центр заповедника",
     "image_url": "https://n-svirsky.ru/upload/photo/losscoptera.jpeg",
     "transport": "Пешая"},

    {"id": 3, "title": "История флота: от Петра до наших дней", "type": "История", "capacity": "Групповая",
     "duration_days": '1 день', "price": 3500,
     "guide": "Михаил Андреевич",
     "description": "Прогулка по набережной Лодейного Поля, где строились первые корабли Балтийского флота. Посещение краеведческого музея и осмотр памятных мест.",
     "phone_number": "+7 (921) 210 21 21", "route": "Набережная → Музей",
     "image_url": "https://историческийбагаж.рф/static/place/hr_8538-4554.jpg",
     "transport": "Пешая"},

    {"id": 4, "title": "Магия оятской керамики", "type": "Ремёсла", "capacity": "Индивидуальная", "duration_days": '1 день',
     "price": 4500, "guide": "Елена Сергеевна",
     "description": "Мастер-класс в центре гончарного промысла в Алёховщине. Вы сами создадите изделие из местной глины под руководством мастера.",
     "phone_number": "+7 (921) 111 22 33", "route": "Алёховщина (Центр ремёсел)",
     "image_url": "https://mirdcer.ru/images/0_2024/06_LA/440.JPG",
     "transport": "Комбинированная"},

    {"id": 5, "title": "Паломнический круг: Монастыри Присвирья", "type": "Духовность", "capacity": "Групповая",
     "duration_days": '1 день',
     "price": 5000, "guide": "Отец Дмитрий",
     "description": "Посещение Александро-Свирского и Покрово-Тервенического монастырей. Рассказ об истории обителей и чудотворных иконах.",
     "phone_number": "+7 (921) 999 88 77", "route": "Старая Слобода → Тервеничи",
     "image_url": "https://img-fotki.yandex.ru/get/6837/81294148.11/0_cc3ba_583e5c55_XL.jpg",
     "transport": "Автобусная"},

    {"id": 6, "title": "Индустриальный гигант: Нижне-Свирская ГЭС", "type": "Индустриальный туризм",
     "capacity": "Семейная", "duration_days": '1 день',
     "price": 4000, "guide": "Сергей Иванович",
     "description": "Экскурсия к плотине ГЭС. Вы увидите, как укрощают реку Свирь, и узнаете об истории строительства этого грандиозного сооружения.",
     "phone_number": "+7 (921) 444 55 66", "route": "Свирьстрой (ГЭС)",
     # Вставь сюда прямую ссылку на фото ГЭС (например, с Wikimedia Commons)
     "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/7/72/Вид_на_плотину_с_крыши_главного_корпуса.jpg/1280px-Вид_на_плотину_с_крыши_главного_корпуса.jpg",
     "transport": "Автобусная"},

    {"id": 7, "title": "Квест 'Тайны северной земли'", "type": "Активный", "capacity": "Семейная", "duration_days": '1 день',
     "price": 5500, "guide": "Алексей Владимирович",
     "description": "Игровой маршрут с загадками и поиском артефактов. Подходит для семей с детьми и молодежных компаний. Элементы ориентирования на местности.",
     "phone_number": "+7 (921) 777 88 99", "route": "Лесные тропы у Янеги",
     "image_url": "https://avatars.mds.yandex.net/i?id=00438b97c5a6e22b9fcd43b1a00b5fae_l-5220454-images-thumbs&n=13",
     "transport": "Пешая"},

    {"id": 8, "title": "Вкусы Севера: Гастротур", "type": "Гастрономия", "capacity": "Индивидуальная",
     "duration_days": '1 день',
     "price": 6500, "guide": "Ольга Николаевна",
     "description": "Дегустация северной кухни: калитки, пироги с грибами, травяные чаи. Посещение местных ферм и пекарни.",
     "phone_number": "+7 (921) 333 22 11", "route": "Алёховщина → Тервеничи",
     "image_url": "http://sladostisevera.ru/d/kalitka_karelskaya_rzhanaya.jpg",
     "transport": "Автобусная"},

    {"id": 9, "title": "Рассвет над Свирью: Фото-прогулка", "type": "Творчество", "capacity": "Индивидуальная",
     "duration_days": '1 день',
     "price": 7000, "guide": "Марина Викторовна",
     "description": "Ранний выезд на точку рассвета. Гид-фотограф поможет поймать лучший свет и расскажет о композиции. Идеально для любителей фотографии.",
     "phone_number": "+7 (921) 123 45 67", "route": "Побережье Свири (район Рассвета)",
     "image_url": "https://avatars.mds.yandex.net/i?id=c6b492e519efe6d3ae1fe8d603bae4ebec230a7d-5235458-images-thumbs&n=13",
     "transport": "Комбинированная"},

    {"id": 10, "title": "Этно-деревня: Жизнь северян", "type": "Этнография", "capacity": "Групповая",
     "duration_days": '1 день',
     "price": 4200, "guide": "Валентина Михайловна",
     "description": "Экскурсия в Андреевщину (центр «Кондуши»). Знакомство с карельским бытом, песнями и традиционными ремёслами.",
     "phone_number": "+7 (921) 987 65 43", "route": "Андреевщина (Центр «Кондуши»)",
     "image_url": "https://avatars.mds.yandex.net/i?id=6bc5c8350c9ec9a72883bc56011d45ce_l-5504208-images-thumbs&n=13",
     "transport": "Автобусная"}
]


df = pd.DataFrame(excursions)

# --- БАЗА ДАННЫХ ЛОКАЦИЙ ДЛЯ КАРТЫ ---
map_locations = [
    {"name": "Лодейное Поле",
     "desc": "Колыбель Балтийского флота. Здесь воздух пропитан запахом сосновой смолы и солёного ветра Свири."},
    {"name": "Старая Слобода",
     "desc": "Александро-Свирский монастырь. Белокаменные стены, отражающиеся в воде, кажутся миражом из Древней Руси."},
    {"name": "Свирьстрой",
     "desc": "Нижне-Свирская ГЭС — бетонный исполин, укротивший стихию. Здесь можно почувствовать, как энергия воды превращается в свет."},
    {"name": "Алёховщина",
     "desc": "Сердце оятской керамики. Здесь из красной глины рождаются не просто горшки, а хранители тепла человеческих рук."},
    {"name": "Тервеничи",
     "desc": "Покрово-Тервенический монастырь. Место, где северная строгость встречается с тихой благодатью."},
    {"name": "Доможирово", "desc": "Вход в Нижне-Свирский заповедник. Царство болот, глухарей и редких орхидей."},
    {"name": "Оять",
     "desc": "Введено-Оятский монастырь и целебный минеральный источник. Место, где время течёт иначе."},
    {"name": "Акулова Гора", "desc": "Кедровая роща среди вековых сосен. Воздух, насыщенный фитонцидами."},
    {"name": "Андреевщина", "desc": "Центр карельской культуры «Кондуши». Знакомство с традициями коренных народов."},
    {"name": "Шамокша",
     "desc": "Деревня с финно-угорским названием. Старинные крестьянские избы рассказывают о быте северян."},
    {"name": "Рассвет",
     "desc": "Место, где можно встретить рассвет над Свирью. Первые лучи солнца золотят водную гладь."},
    {"name": "Янега", "desc": "Тихий уголок сосновых боров. Земля усыпана мягким ковром из мха и черники."}
]

if "is_logged_in" not in st.session_state:
    st.session_state.is_logged_in = False
if "user_email" not in st.session_state:
    st.session_state.user_email = None
if "user_nickname" not in st.session_state:
    st.session_state.user_nickname = None

tab_excursions, tab_map = st.tabs(["🗺️ Экскурсии", "📍 Интерактивная карта"])

with tab_excursions:
    with st.sidebar:
        st.header("👤 Вход / Регистрация")
        if not st.session_state.is_logged_in:
            mode = st.radio("Действие", ["Вход", "Регистрация"])
            email = st.text_input("Email")

            if mode == "Регистрация":
                nickname = st.text_input("Никнейм")
                password = st.text_input("Пароль", type="password")
                if st.button("Зарегистрироваться"):
                    if register_user(email, nickname, password):
                        st.success("Готово! Войдите теперь.")
                        st.rerun()
                    else:
                        st.error("Такой email уже есть")
            else:
                password = st.text_input("Пароль", type="password")
                if st.button("Войти"):
                    success, nick = login_user(email, password)
                    if success:
                        st.session_state.is_logged_in = True
                        st.session_state.user_email = email
                        st.session_state.user_nickname = nick
                        st.rerun()
                    else:
                        st.error("Неверный логин или пароль")
        else:
            st.info(f"Привет, {st.session_state.user_nickname}!")
            if st.button("Выйти"):
                st.session_state.is_logged_in = False
                st.rerun()

    st.header("🗺️ Экскурсии в Лодейнопольском районе")
    st.caption(
        "Выберите фильтры, чтобы найти идеальный маршрут. Теперь можно выбрать тип передвижения: пешком, на автобусе или смешанный вариант.")

    # --- НОВЫЕ ФИЛЬТРЫ (3 колонки) ---
    col1, col2, col3 = st.columns(3)
    with col1:
        types_opts = ["Все"] + sorted(df["type"].unique().tolist())
        sel_type = st.selectbox("Тип экскурсии", types_opts)
    with col2:
        caps_opts = ["Все", "Индивидуальная", "Семейная", "Групповая"]
        sel_cap = st.selectbox("Формат", caps_opts)
    with col3:
        # Новый фильтр по транспорту
        trans_opts = ["Все", "Пешая", "Автобусная", "Комбинированная"]
        sel_trans = st.selectbox("Тип передвижения", trans_opts)

    df_f = df.copy()
    if sel_type != "Все":
        df_f = df_f[df_f["type"] == sel_type]
    if sel_cap != "Все":
        df_f = df_f[df_f["capacity"].str.contains(sel_cap, na=False)]
    # Новая логика фильтрации по транспорту
    if sel_trans != "Все":
        df_f = df_f[df_f["transport"] == sel_trans]

    pop_scores = []
    for _, r in df_f.iterrows():
        avg, cnt = get_stats_for_excursion(r["id"])
        pop_scores.append(avg * cnt if cnt > 0 else 0)
    df_f["pop_score"] = pop_scores
    df_f = df_f.sort_values("pop_score", ascending=False)

    if df_f.empty:
        st.info("Ничего не найдено по выбранным фильтрам. Попробуйте снять одно из ограничений.")
    else:
        for _, row in df_f.iterrows():
            with st.container():
                st.image(row["image_url"], width=500)
                st.subheader(row["title"])

                cols = st.columns(6)
                cols[0].write(f"**Тип:** {row['type']}")
                cols[1].write(f"**Формат:** {row['capacity']}")
                # Добавляем значок транспорта прямо в карточку
                trans_icon = "🚶" if row["transport"] == "Пешая" else (
                    "🚌" if row["transport"] == "Автобусная" else "🚶🚌")
                cols[2].write(f"**Передвижение:** {trans_icon} {row['transport']}")
                cols[3].write(f"**Цена:** {row['price']:,} ₽")
                cols[4].write(f"**Телефон:** {row['phone_number']}")
                cols[5].write(f"**Длительность**  {row['duration_days']}")


                st.write(f"**Гид:** {row['guide']} | **Маршрут:** {row['route']}")

                avg_r, cnt_r = get_stats_for_excursion(row["id"])
                stars = "⭐" * int(avg_r) + "★" * (5 - int(avg_r))
                st.info(f"{stars} Рейтинг: {avg_r}/5.0 ({cnt_r} отзывов)")

                with st.expander("📝 Описание и атмосфера"):
                    st.write(row["description"])
                    st.info("💡 Совет: Для пеших экскурсий обязательно возьмите воду и удобную обувь!")

                with st.expander("💬 Отзывы туристов"):
                    reviews = get_reviews_for_excursion(row["id"])
                    if reviews:
                        for rev in reviews:
                            with st.chat_message("assistant"):
                                s_disp = "⭐" * rev["rating"] + "★" * (5 - rev["rating"])
                                if rev["photo_path"]:
                                    try:
                                        st.image(os.path.join(UPLOAD_DIR, rev["photo_path"]), width=300)
                                    except:
                                        pass
                                st.markdown(f"**@{rev['nickname']} ({s_disp}):** {rev['text']}")
                    else:
                        st.info("Отзывов пока нет. Станьте первым!")

                    if st.session_state.is_logged_in:
                        st.markdown("---")
                        st.subheader("Оставить отзыв")
                        r_rating = st.slider("Оценка", 1, 5, 5, key=f"slider_{row['id']}")
                        r_text = st.text_area("Текст отзыва", height=80, key=f"text_{row['id']}")
                        r_photo = st.file_uploader("Загрузите фото с устройства", type=["png", "jpg", "jpeg"],
                                                   key=f"photo_{row['id']}")

                        if st.button("Опубликовать", key=f"btn_{row['id']}"):
                            if r_text.strip():
                                photo_filename = save_uploaded_file(r_photo)
                                add_review(row["id"], st.session_state.user_email, r_text, photo_filename, r_rating)
                                st.success("Отзыв и фото добавлены!")
                                st.rerun()
                            else:
                                st.warning("Текст отзыва не может быть пустым")
                    else:
                        st.warning("Войдите в аккаунт, чтобы оставить отзыв.")

                st.divider()

with tab_map:
    st.header("📍 Схема Лодейнопольского района")
    st.caption("Нажмите на название пункта, чтобы узнать о нём подробнее.")

    col_map, col_buttons = st.columns([4, 2])

    with col_map:
        try:
            st.image("map.png", caption="Интерактивная схема района", use_container_width=True)
        except FileNotFoundError:
            st.warning("⚠️ Файл map.png не найден!")
            st.image("https://via.placeholder.com/800x600?text=Карта+района", use_container_width=True)

    with col_buttons:
        # 1. ЛЕГЕНДА НАД КНОПКАМИ
        st.subheader("🗺️ Легенда карты")
        st.write("На нашей карте отмечены «места силы» района. Каждое место связано с определёнными маршрутами.")
        st.divider()

        st.subheader("🏙️ Населённые пункты и места силы")

        # Инициализация состояния, если его нет
        if "selected_city" not in st.session_state:
            st.session_state.selected_city = None
            st.session_state.is_rerun = False


        unique_locations = []
        seen_names = set()
        for loc in map_locations:
            if loc["name"] not in seen_names:
                unique_locations.append(loc)
                seen_names.add(loc["name"])


        # Цикл по уникальным локациям
        for loc in unique_locations:
            # Кнопка
            if st.button(loc["name"], key=f"btn_{loc['name']}", use_container_width=True):
                # При нажатии жестко устанавливаем имя выбранной локации
                st.session_state.selected_city = loc["name"]
                st.session_state.is_rerun = False

            # Блок описания: показывается ТОЛЬКО если имя совпадает с выбранным
            if st.session_state.selected_city == loc["name"]:
                with st.container():
                    if not st.session_state.is_rerun:
                        st.session_state.is_rerun = True
                        st.rerun()
                    st.session_state.selected_city = loc["name"]
                    st.success(f"✅ Вы выбрали: {loc['name']}", icon="📌")

                    # Основной текст описания
                    st.write(f"**{loc['desc']}**")

                # Разделитель только ПОСЛЕ описания выбранной кнопки
                st.divider()

            # Если кнопка НЕ выбрана — мы ничего не рисуем под ней.
            # Никаких пустых строк, никаких разделителей. Чисто.
