# LinkedIn article 0 — series introduction

**Post title:** I spent 6 weekends building a "People Analytics" platform from scratch. Here's why — and what I learned.

---

Over the past six weekends, I built a complete system for turning messy HR data into clear, trustworthy answers about a workforce — things like *how is headcount trending, why are people leaving, and where do candidates drop out of our hiring process.*

This is the introduction to a five-part series where I walk through how it works, the decisions behind it, and the surprises along the way. I'll explain things in plain language first, then go deeper for the technical folks.

---

**What I built (in plain terms)**

The project is called `workforce-intelligence-platform`. Think of it as four connected parts that take raw people data and turn it into insight you can trust:

1. **Gathering the data** — Most companies keep HR information in several disconnected places: one tool for employee records (like Workday), another for hiring (like Greenhouse), a spreadsheet here and there. This part automatically pulls all of that into one organized, reliable place — so you're not stitching together exports by hand.

2. **Making AI assistants safe and accurate** — If you want an AI chatbot to answer HR questions, you have to make sure it gives correct answers *and* never sees private employee data it shouldn't. This part scores how good the AI's answers are and strips out sensitive information before it ever reaches the AI.

3. **Protecting sensitive information** — HR data includes some of the most private information a company holds (salaries, personal details, performance notes). This part keeps a clear record of what's sensitive, controls who can see what, and tracks who looked at what — automatically.

4. **The dashboard people actually use** — A simple, visual web app showing headcount trends, attrition (who's leaving and why), and the recruiting funnel. This is the part a non-technical stakeholder opens to get answers without writing a single line of code. *(Live link coming once it's deployed.)*

Behind the scenes, a "scheduler" keeps all four parts running in the right order on a regular basis — so the data stays fresh and the dashboard is always up to date without anyone pressing a button.

---

**Why People Analytics specifically**

I've spent the last several years building large-scale data systems in advertising, media, and platform analytics. The underlying engineering skills carry over completely. But the *people* side is different in important ways: measuring headcount and attrition isn't the same as tracking ad clicks, the questions are different, and — crucially — employee data comes with much higher expectations around privacy and access.

Building this platform meant learning those differences on purpose, rather than assuming they'd be obvious.

---

**What the series covers**

- **Part 1 — Getting the data in:** how I connect to HR systems and bring everything into one reliable source.
- **Part 2 — Trustworthy AI for HR:** how I make AI answers accurate while keeping private data protected.
- **Part 3 — Protecting sensitive data:** how access is controlled and every access is tracked.
- **Part 4 — The dashboard:** designing something genuinely useful for non-technical teams.

Each article starts with the "why" anyone can follow, then includes the technical depth for engineers who want it.

---

**The whole project is public** — all the code and configuration is on GitHub.

[GitHub link] · [Live dashboard link]

If you work in HR, recruiting, or analytics — or you're just curious how this kind of system comes together — I'd genuinely love to hear what you're working on.

---

*#dataengineering #peopleanalytics #hranalytics #airflow #dbt #streamlit #python #postgres*
