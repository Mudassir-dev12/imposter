#!/usr/bin/env python3
"""
generate_proposal_pdf.py
Generates a comprehensive, professional Project Proposal PDF for the "Impostor" project.
Formed into a balanced, publication-grade 4-page specification with custom styling.
"""

import sys
import os
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, HRFlowable
)
from reportlab.pdfgen import canvas

class NumberedCanvas(canvas.Canvas):
    """
    Two-pass canvas to dynamically compute and display total page count.
    Adds header and footer to every page except the cover page.
    """
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_page_decorations(num_pages)
            super().showPage()
        super().save()

    def draw_page_decorations(self, total_pages):
        self.saveState()
        self.setFont("Helvetica-Bold", 7.5)
        self.setFillColor(colors.HexColor("#718096"))

        # Running Header (Pages 2+)
        if self._pageNumber > 1:
            self.drawString(36, letter[1] - 26, "PROJECT PROPOSAL: IMPOSTOR (LOCAL P2P MULTIPLAYER ENGINE)")
            self.setFont("Helvetica", 7.5)
            self.drawRightString(letter[0] - 36, letter[1] - 26, "SYSTEM SPECIFICATION & CONTRIBUTION ROLES")
            self.setStrokeColor(colors.HexColor("#CBD5E0"))
            self.setLineWidth(0.5)
            self.line(36, letter[1] - 30, letter[0] - 36, letter[1] - 30)

        # Running Footer (All Pages)
        self.setFont("Helvetica", 7.5)
        self.setStrokeColor(colors.HexColor("#CBD5E0"))
        self.setLineWidth(0.5)
        self.line(36, 32, letter[0] - 36, 32)
        self.drawString(36, 22, "Confidential - Academic Project Proposal & Engineering Architecture")
        page_text = f"Page {self._pageNumber} of {total_pages}"
        self.drawRightString(letter[0] - 36, 22, page_text)

        self.restoreState()


def create_proposal_pdf(output_filename="PROJECT_PROPOSAL.pdf"):
    # 0.5 inch (36 pt) side margins, 36 pt top/bottom for maximum clean printable area
    doc = SimpleDocTemplate(
        output_filename,
        pagesize=letter,
        leftMargin=36,
        rightMargin=36,
        topMargin=36,
        bottomMargin=36
    )

    styles = getSampleStyleSheet()

    # Premium Professional Palette
    PRIMARY = colors.HexColor("#1A365D")   # Deep Navy
    SECONDARY = colors.HexColor("#2B6CB0") # Slate Blue
    ACCENT = colors.HexColor("#2C7A7B")    # Teal Accent
    DARK_TEXT = colors.HexColor("#2D3748") # Charcoal Body Text
    LIGHT_BG = colors.HexColor("#F7FAFC")  # Clean Light Gray
    BORDER_COLOR = colors.HexColor("#CBD5E0")

    # Typography Styles
    title_style = ParagraphStyle(
        'CoverTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=20,
        leading=24,
        textColor=PRIMARY,
        spaceAfter=3
    )

    subtitle_style = ParagraphStyle(
        'CoverSubtitle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=10,
        leading=13.5,
        textColor=SECONDARY,
        spaceAfter=8
    )

    meta_style = ParagraphStyle(
        'CoverMeta',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8,
        leading=11,
        textColor=DARK_TEXT
    )

    h1_style = ParagraphStyle(
        'SectionH1',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=11.5,
        leading=15,
        textColor=PRIMARY,
        spaceBefore=7,
        spaceAfter=3,
        keepWithNext=True
    )

    body_style = ParagraphStyle(
        'BodyDark',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.2,
        leading=11.5,
        textColor=DARK_TEXT,
        spaceAfter=3.5
    )

    bullet_style = ParagraphStyle(
        'BulletText',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.2,
        leading=11,
        textColor=DARK_TEXT,
        leftIndent=10,
        firstLineIndent=-7,
        spaceAfter=2
    )

    table_header_style = ParagraphStyle(
        'TableHeader',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8,
        leading=10.5,
        textColor=colors.white,
        alignment=0
    )

    table_cell_style = ParagraphStyle(
        'TableCell',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=7.8,
        leading=10,
        textColor=DARK_TEXT
    )

    table_cell_bold = ParagraphStyle(
        'TableCellBold',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=7.8,
        leading=10,
        textColor=PRIMARY
    )

    callout_style = ParagraphStyle(
        'CalloutText',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=7.8,
        leading=10.5,
        textColor=DARK_TEXT
    )

    story = []

    # =========================================================================
    # PAGE 1: TITLE, EXECUTIVE SUMMARY & TECHNICAL ARCHITECTURE
    # =========================================================================
    story.append(Paragraph("PROJECT PROPOSAL & TECHNICAL SPECIFICATION", ParagraphStyle(
        'Tag', fontName='Helvetica-Bold', fontSize=8, textColor=ACCENT, spaceAfter=2
    )))
    story.append(Paragraph("IMPOSTOR: Local Peer-to-Peer Social Deduction Game", title_style))
    story.append(Paragraph("Zero-Cloud Offline Multiplayer Engine with Embedded CPython & Custom DSA Architecture", subtitle_style))
    story.append(HRFlowable(width="100%", thickness=1.5, color=PRIMARY, spaceBefore=0, spaceAfter=6))

    # Meta Table: Overview & Scope
    meta_data = [
        [
            Paragraph("<b>Project Category:</b> Distributed Mobile Systems & Custom DSA", meta_style),
            Paragraph("<b>Target Platform:</b> Android (Mobile) & Cross-Platform (Flutter)", meta_style)
        ],
        [
            Paragraph("<b>Core Stack:</b> Flutter / Dart, Python 3.12 (CPython), WebSockets", meta_style),
            Paragraph("<b>Team Composition:</b> 3 Dedicated Engineering Team Members", meta_style)
        ],
        [
            Paragraph("<b>Networking Model:</b> Local Wi-Fi / Hotspot Peer-to-Peer (Zero-Cloud)", meta_style),
            Paragraph("<b>Document Version:</b> 1.0 (Full Architecture, Roadmap & Contribution Roles)", meta_style)
        ]
    ]
    meta_table = Table(meta_data, colWidths=[268, 272])
    meta_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), LIGHT_BG),
        ('BOX', (0,0), (-1,-1), 0.75, BORDER_COLOR),
        ('INNERGRID', (0,0), (-1,-1), 0.5, BORDER_COLOR),
        ('TOPPADDING', (0,0), (-1,-1), 3.5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3.5),
        ('LEFTPADDING', (0,0), (-1,-1), 6),
        ('RIGHTPADDING', (0,0), (-1,-1), 6),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 4))

    # 1. Executive Summary & Problem Statement
    story.append(Paragraph("1. Executive Summary & Problem Statement", h1_style))
    story.append(Paragraph(
        "<b>Executive Summary:</b> <i>Impostor</i> is an offline-first social deduction mobile game engineered to deliver "
        "instant, high-fidelity party gaming completely independent of cloud servers, external databases, or internet connectivity. "
        "By packaging an entire asynchronous Python 3.12 game engine directly inside a Flutter mobile application, any player "
        "can create a game room over a local Wi-Fi router or portable mobile hotspot, allowing nearby players to connect peer-to-peer "
        "via fast camera QR scanning or manual IP entry with microsecond responsiveness.",
        body_style
    ))
    story.append(Paragraph(
        "<b>Problem Statement:</b> Commercial multiplayer party titles (such as <i>Among Us</i> or <i>Jackbox</i>) universally "
        "mandate external cloud matchmaking and persistent internet connections. This creates four severe failure modes: "
        "(1) <i>Zero Offline Capability:</i> Games are unplayable during flights, road trips, outdoor gatherings, or in areas with captive portals; "
        "(2) <i>Server Deprecation & Outages:</i> Titles become unplayable whenever central servers experience outages or developer sunsets; "
        "(3) <i>Privacy Hazards:</i> User interactions and device metadata are routed through third-party telemetry servers; and "
        "(4) <i>Packet Latency:</i> Unnecessary round-trips to distant cloud servers impair live, real-time deduction.",
        body_style
    ))
    story.append(Paragraph(
        "<b>Proposed Solution:</b> <i>Impostor</i> decentralizes the game loop entirely. The host phone runs both the Flutter UI "
        "and a local background Python WebSocket server. Communication occurs exclusively within the local subnet, delivering "
        "100% data privacy, zero recurring cloud hosting costs, and resilience across any environment.",
        body_style
    ))

    # 2. Key Technical Innovations
    story.append(Paragraph("2. Core Technical Innovations & Mobile Systems Engineering", h1_style))
    arch_box_data = [
        [
            Paragraph("<b>A. In-Process Python Supervisor Daemon (Loopback Control Channel)</b><br/>"
                      "Embedded CPython inside Android cannot safely re-initialize once loaded (<code>Py_Initialize()</code> is a process singleton). "
                      "To permit starting and stopping game rooms without restarting the Flutter app, a dedicated supervisor daemon "
                      "(<code>server/embedded_entry.py</code>) runs on an <code>asyncio</code> loop. It exposes a loopback-only control channel strictly "
                      "bound to <code>127.0.0.1:8766</code>, authenticated with a dynamic 256-bit token. Commands (<code>START</code>, <code>STOP</code>, "
                      "<code>STATUS</code>, <code>QUIT</code>) cleanly instantiate and tear down the game server, releasing port 8765 completely on demand.", callout_style)
        ],
        [
            Paragraph("<b>B. Zero-Configuration Local Discovery & Hotspot Fallback Subsystem</b><br/>"
                      "Standard mobile IP lookups fail when the host enables a Portable Hotspot instead of connecting to Wi-Fi. <i>Impostor</i> "
                      "implements a multi-tiered network resolver that enumerates active network interfaces (<code>wlan</code>, <code>ap</code>, <code>softap</code>) "
                      "and filters RFC 1918 private subnets (<code>10.0.0.0/8</code>, <code>172.16.0.0/12</code>, <code>192.168.0.0/16</code>). The host lobby encodes "
                      "the endpoint into an instant QR payload (<code>QrPayload</code>) for camera auto-joining.", callout_style)
        ],
        [
            Paragraph("<b>C. Android 14+ Foreground Service Integration (<code>specialUse</code>)</b><br/>"
                      "To prevent Android OEM battery management from killing the server socket when the host screen dims, the application integrates "
                      "<code>flutter_foreground_task</code> with the Android 14 <code>specialUse</code> foreground service subtype and partial CPU wake locks.", callout_style)
        ]
    ]
    arch_box_table = Table(arch_box_data, colWidths=[540])
    arch_box_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), LIGHT_BG),
        ('BOX', (0,0), (-1,-1), 0.75, BORDER_COLOR),
        ('INNERGRID', (0,0), (-1,-1), 0.5, BORDER_COLOR),
        ('TOPPADDING', (0,0), (-1,-1), 3.5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3.5),
        ('LEFTPADDING', (0,0), (-1,-1), 6),
        ('RIGHTPADDING', (0,0), (-1,-1), 6),
    ]))
    story.append(arch_box_table)

    # PAGE 1 END -> PAGE 2
    story.append(PageBreak())

    # =========================================================================
    # PAGE 2: CUSTOM DSA FOUNDATIONS & ROLE BREAKDOWNS (MEMBERS 1 & 2)
    # =========================================================================
    story.append(Paragraph("3. Custom Data Structures & Algorithmic Foundations (Built from Scratch)", h1_style))
    story.append(Paragraph(
        "A central requirement of the project is that all scheduling, indexing, and state pipeline algorithms are implemented "
        "from first principles in pure Python, bypassing standard library conveniences (e.g., <code>collections.deque</code>, "
        "<code>heapq</code>, or default dictionary room lookups):",
        body_style
    ))

    dsa_table_data = [
        [
            Paragraph("Data Structure", table_header_style),
            Paragraph("Engine Implementation Role", table_header_style),
            Paragraph("Complexity", table_header_style),
            Paragraph("Algorithmic Advantage & Design Rationale", table_header_style)
        ],
        [
            Paragraph("<b>Circular Doubly-Linked List</b><br/><code>CircularLinkedList[T]</code>", table_cell_bold),
            Paragraph("Manages player clue turn rotation and cyclic round progression.", table_cell_style),
            Paragraph("<b>Step:</b> O(1)<br/><b>Append:</b> O(1)<br/><b>Remove:</b> O(1)", table_cell_style),
            Paragraph("Enables infinite circular iteration over active players without modulo indexing; supports seamless O(1) removal of disconnected players mid-round.", table_cell_style)
        ],
        [
            Paragraph("<b>Binary Min-Heap</b><br/><code>MinHeap[T]</code>", table_cell_bold),
            Paragraph("Priority timer scheduler for discussion countdowns and vote deadlines.", table_cell_style),
            Paragraph("<b>Peek:</b> O(1)<br/><b>Push:</b> O(log N)<br/><b>Pop:</b> O(log N)", table_cell_style),
            Paragraph("Enables asynchronous timer management where the 100ms ticker only checks the heap root rather than iterating through all rooms and events.", table_cell_style)
        ],
        [
            Paragraph("<b>FIFO Queue</b><br/><code>Queue[T]</code>", table_cell_bold),
            Paragraph("Serializes incoming player actions, clue submissions, and votes.", table_cell_style),
            Paragraph("<b>Enqueue:</b> O(1)<br/><b>Dequeue:</b> O(1)<br/><b>Peek:</b> O(1)", table_cell_style),
            Paragraph("Guarantees deterministic, sequential event handling and race-condition elimination during concurrent high-frequency vote submissions.", table_cell_style)
        ],
        [
            Paragraph("<b>Chained Hash Table</b><br/><code>ChainedHashTable[K,V]</code>", table_cell_bold),
            Paragraph("Core room registry managing active rooms, codes, and player lookups.", table_cell_style),
            Paragraph("<b>Average:</b> O(1)<br/><b>Worst:</b> O(N)<br/><b>Resize:</b> O(N)", table_cell_style),
            Paragraph("Custom djb2 polynomial hash with separate collision chaining; dynamically doubles capacity at 0.75 load factor to ensure constant-time retrieval.", table_cell_style)
        ]
    ]
    dsa_table = Table(dsa_table_data, colWidths=[120, 140, 95, 185])
    dsa_table.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), PRIMARY),
        ('BOX', (0,0), (-1,-1), 0.75, BORDER_COLOR),
        ('INNERGRID', (0,0), (-1,-1), 0.5, BORDER_COLOR),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, LIGHT_BG]),
        ('TOPPADDING', (0,0), (-1,-1), 3),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3),
        ('LEFTPADDING', (0,0), (-1,-1), 5),
        ('RIGHTPADDING', (0,0), (-1,-1), 5),
    ]))
    story.append(dsa_table)
    story.append(Spacer(1, 5))

    # 4. Three-Member Team Roles - Part 1
    story.append(Paragraph("4. Team Structure & Contribution Roles (3 Members)", h1_style))
    story.append(Paragraph(
        "To achieve balanced workload distribution, modular architectural separation, and clear engineering accountability, "
        "the project is split across three dedicated domain leads:",
        body_style
    ))

    # Member 1 Box
    m1_box = [
        [
            Paragraph("<b>MEMBER 1: Core Engine & Algorithmic Logic Lead</b> | <i>Stack: Python 3.12, Pytest, Custom Object-Oriented DSA</i>", ParagraphStyle(
                'M1H', fontName='Helvetica-Bold', fontSize=8.2, textColor=PRIMARY
            ))
        ],
        [
            Paragraph(
                "• <b>Custom DSA Engine:</b> Architect and code all 4 foundational data structures from scratch (<code>CircularLinkedList</code>, "
                "<code>MinHeap</code>, <code>Queue</code>, <code>ChainedHashTable</code> with djb2 hashing), including custom iterators and dynamic resizing.<br/>"
                "• <b>Game State Machine:</b> Construct the complete room lifecycle finite state machine (<code>Lobby</code>, <code>RoleReveal</code>, "
                "<code>CluePhase</code>, <code>Discussion</code>, <code>Voting</code>, <code>Results</code>) in <code>engine/game.py</code>.<br/>"
                "• <b>Word Bank & Validation:</b> Build the word repository (<code>engine/words.py</code>) supporting 120+ curated words across 10 categories, "
                "semantic clue validation rules, and secret word matching algorithms.<br/>"
                "• <b>Asymmetric Information Secrecy:</b> Enforce mathematical client-view filtering (crew views never reveal Impostor identity during active play; "
                "impostor views never reveal the Secret Word prior to round resolution).<br/>"
                "• <b>Verification:</b> Author comprehensive Pytest suites (<code>test_structures.py</code>, <code>test_engine_flow.py</code>, <code>test_protocol.py</code>).",
                body_style
            )
        ]
    ]
    t_m1 = Table(m1_box, colWidths=[540])
    t_m1.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#EBF8FF")),
        ('BACKGROUND', (0,1), (-1,1), colors.white),
        ('BOX', (0,0), (-1,-1), 0.75, colors.HexColor("#3182CE")),
        ('TOPPADDING', (0,0), (-1,-1), 3),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3),
        ('LEFTPADDING', (0,0), (-1,-1), 6),
        ('RIGHTPADDING', (0,0), (-1,-1), 6),
    ]))
    story.append(t_m1)
    story.append(Spacer(1, 4))

    # Member 2 Box
    m2_box = [
        [
            Paragraph("<b>MEMBER 2: Embedded Systems & Server Architecture Lead</b> | <i>Stack: Python asyncio, websockets, serious_python, Bash</i>", ParagraphStyle(
                'M2H', fontName='Helvetica-Bold', fontSize=8.2, textColor=PRIMARY
            ))
        ],
        [
            Paragraph(
                "• <b>In-Process Supervisor:</b> Design the long-lived supervisor daemon (<code>server/embedded_entry.py</code>) running an <code>asyncio</code> "
                "event loop, overcoming CPython process singleton constraints on mobile OSs.<br/>"
                "• <b>Loopback Control Protocol:</b> Implement the authenticated loopback control channel on <code>127.0.0.1:8766</code> with random 256-bit token "
                "authorization, processing <code>START</code>, <code>STOP</code>, <code>STATUS</code>, and <code>QUIT</code> commands safely.<br/>"
                "• <b>Teardown & Port Release:</b> Engineer graceful shutdown routines in <code>server/main.py</code> and <code>server/connection_manager.py</code> "
                "(broadcasting <code>room_closed</code>, closing sockets, canceling ticker tasks, and fully releasing port 8765).<br/>"
                "• <b>Automated Android Packaging:</b> Create the packaging pipeline (<code>scripts/package_python.sh</code>) to bundle pure-Python wheels "
                "(<code>websockets==17.3</code>) and engine files into compact 32KB assets for Android ABIs (arm64, armeabi, x86_64).<br/>"
                "• <b>Verification:</b> Author supervisor lifecycle and concurrency tests (<code>tests/test_supervisor.py</code>, <code>tests/test_server_integration.py</code>).",
                body_style
            )
        ]
    ]
    t_m2 = Table(m2_box, colWidths=[540])
    t_m2.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#F0FFF4")),
        ('BACKGROUND', (0,1), (-1,1), colors.white),
        ('BOX', (0,0), (-1,-1), 0.75, colors.HexColor("#38A169")),
        ('TOPPADDING', (0,0), (-1,-1), 3),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3),
        ('LEFTPADDING', (0,0), (-1,-1), 6),
        ('RIGHTPADDING', (0,0), (-1,-1), 6),
    ]))
    story.append(t_m2)

    # PAGE 2 END -> PAGE 3
    story.append(PageBreak())

    # =========================================================================
    # PAGE 3: MEMBER 3 ROLE & DETAILED RACI RESPONSIBILITY MATRIX
    # =========================================================================
    # Member 3 Box
    m3_box = [
        [
            Paragraph("<b>MEMBER 3: Mobile Client, UI/UX & Native Android Lead</b> | <i>Stack: Dart, Flutter Framework, Android NDK, Kotlin/Gradle</i>", ParagraphStyle(
                'M3H', fontName='Helvetica-Bold', fontSize=8.2, textColor=PRIMARY
            ))
        ],
        [
            Paragraph(
                "• <b>Flutter UI/UX Architecture:</b> Design and implement the complete suite of reactive client screens (<code>HomeScreen</code>, "
                "<code>LobbyScreen</code>, <code>RoleRevealScreen</code>, <code>ClueSubmissionScreen</code>, <code>VotingScreen</code>, <code>ResultsScreen</code>).<br/>"
                "• <b>Host Controller State Machine:</b> Develop <code>HostService</code> and <code>HostControlClient</code> in Dart, managing "
                "supervisor launch, token generation, TCP control channel communication, socket polling, and emergency process exit fallbacks.<br/>"
                "• <b>Camera QR Scanning & Generation:</b> Integrate <code>mobile_scanner</code> with custom viewfinder overlays and <code>qr_flutter</code> "
                "rendering for zero-friction peer-to-peer room pairing.<br/>"
                "• <b>Android Native Services:</b> Configure Android 14 <code>specialUse</code> Foreground Service notifications and CPU wake locks "
                "(<code>wakelock_plus</code>) to ensure uninterrupted hosting when the host device is locked or backgrounded.<br/>"
                "• <b>Network Discovery & Debug UI:</b> Build <code>NetworkIpHelper</code> for Wi-Fi and hotspot RFC 1918 IP resolution, and implement the "
                "<code>EmbeddedServerDebugScreen</code> providing live telemetry and manual server control.",
                body_style
            )
        ]
    ]
    t_m3 = Table(m3_box, colWidths=[540])
    t_m3.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), colors.HexColor("#FAF5FF")),
        ('BACKGROUND', (0,1), (-1,1), colors.white),
        ('BOX', (0,0), (-1,-1), 0.75, colors.HexColor("#805AD5")),
        ('TOPPADDING', (0,0), (-1,-1), 3),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3),
        ('LEFTPADDING', (0,0), (-1,-1), 6),
        ('RIGHTPADDING', (0,0), (-1,-1), 6),
    ]))
    story.append(t_m3)
    story.append(Spacer(1, 5))

    # 5. Detailed RACI Matrix
    story.append(Paragraph("5. RACI Responsibility & Accountability Assignment Matrix", h1_style))
    story.append(Paragraph(
        "Definition of terms: <b>R</b> = Responsible (performs work), <b>A</b> = Accountable (final decision/ownership), "
        "<b>C</b> = Consulted (provides input), <b>I</b> = Informed (kept updated of progress).",
        body_style
    ))

    raci_data = [
        [
            Paragraph("Deliverable / Workstream", table_header_style),
            Paragraph("Member 1 (Engine)", table_header_style),
            Paragraph("Member 2 (Systems)", table_header_style),
            Paragraph("Member 3 (Client)", table_header_style)
        ],
        [
            Paragraph("Custom DSA Core (Linked List, Heap, Queue, Hash Table)", table_cell_bold),
            Paragraph("<b>Responsible / Accountable</b>", table_cell_style),
            Paragraph("Consulted (API Interface)", table_cell_style),
            Paragraph("Informed", table_cell_style)
        ],
        [
            Paragraph("Game Rules Finite State Machine & Secrecy Filters", table_cell_bold),
            Paragraph("<b>Responsible / Accountable</b>", table_cell_style),
            Paragraph("Consulted (Async hooks)", table_cell_style),
            Paragraph("Consulted (UI States)", table_cell_style)
        ],
        [
            Paragraph("Word Repository & Semantic Clue Matcher", table_cell_bold),
            Paragraph("<b>Responsible / Accountable</b>", table_cell_style),
            Paragraph("Informed", table_cell_style),
            Paragraph("Consulted (Language UI)", table_cell_style)
        ],
        [
            Paragraph("In-Process Supervisor & Loopback Control Channel", table_cell_bold),
            Paragraph("Informed", table_cell_style),
            Paragraph("<b>Responsible / Accountable</b>", table_cell_style),
            Paragraph("Consulted (Socket Spec)", table_cell_style)
        ],
        [
            Paragraph("WebSocket Server, Ticker Loop & Socket Teardown", table_cell_bold),
            Paragraph("Consulted (Engine Calls)", table_cell_style),
            Paragraph("<b>Responsible / Accountable</b>", table_cell_style),
            Paragraph("Consulted (Disconnect UI)", table_cell_style)
        ],
        [
            Paragraph("Python ABI Bundling & Packaging Script", table_cell_bold),
            Paragraph("Informed", table_cell_style),
            Paragraph("<b>Responsible / Accountable</b>", table_cell_style),
            Paragraph("Consulted (Assets)", table_cell_style)
        ],
        [
            Paragraph("Flutter Client Screens, State & View Models", table_cell_bold),
            Paragraph("Consulted (State Display)", table_cell_style),
            Paragraph("Informed", table_cell_style),
            Paragraph("<b>Responsible / Accountable</b>", table_cell_style)
        ],
        [
            Paragraph("HostService Daemon Manager & Port Polling", table_cell_bold),
            Paragraph("Informed", table_cell_style),
            Paragraph("Consulted (Control Commands)", table_cell_style),
            Paragraph("<b>Responsible / Accountable</b>", table_cell_style)
        ],
        [
            Paragraph("Android Foreground Service & CPU WakeLocks", table_cell_bold),
            Paragraph("Informed", table_cell_style),
            Paragraph("Consulted (Thread Safety)", table_cell_style),
            Paragraph("<b>Responsible / Accountable</b>", table_cell_style)
        ],
        [
            Paragraph("Camera QR Scanning & Network Interface Parser", table_cell_bold),
            Paragraph("Informed", table_cell_style),
            Paragraph("Informed", table_cell_style),
            Paragraph("<b>Responsible / Accountable</b>", table_cell_style)
        ],
        [
            Paragraph("Comprehensive Testing, Profiling & Documentation", table_cell_bold),
            Paragraph("Responsible (Pytest Suite)", table_cell_style),
            Paragraph("Responsible (Supervisor)", table_cell_style),
            Paragraph("Responsible (Flutter/UI)", table_cell_style)
        ]
    ]
    t_raci = Table(raci_data, colWidths=[190, 115, 115, 120])
    t_raci.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), PRIMARY),
        ('BOX', (0,0), (-1,-1), 0.75, BORDER_COLOR),
        ('INNERGRID', (0,0), (-1,-1), 0.5, BORDER_COLOR),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, LIGHT_BG]),
        ('TOPPADDING', (0,0), (-1,-1), 2.5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 2.5),
        ('LEFTPADDING', (0,0), (-1,-1), 5),
        ('RIGHTPADDING', (0,0), (-1,-1), 5),
    ]))
    story.append(t_raci)

    # PAGE 3 END -> PAGE 4
    story.append(PageBreak())

    # =========================================================================
    # PAGE 4: PHASES, TIMELINE, RISKS & VERIFICATION ACCEPTANCE
    # =========================================================================
    story.append(Paragraph("6. Project Implementation Timeline & Milestone Deliverables", h1_style))

    phases_data = [
        [
            Paragraph("Phase / Milestone", table_header_style),
            Paragraph("Key Technical Objectives & Outputs", table_header_style),
            Paragraph("Duration", table_header_style),
            Paragraph("Primary Lead", table_header_style)
        ],
        [
            Paragraph("<b>Phase 1: DSA & Engine Core</b>", table_cell_bold),
            Paragraph("Design 4 custom data structures, word repository, and game state machine engine.", table_cell_style),
            Paragraph("Weeks 1 - 2", table_cell_style),
            Paragraph("Member 1", table_cell_style)
        ],
        [
            Paragraph("<b>Phase 2: Networking & Protocol</b>", table_cell_bold),
            Paragraph("Asyncio WebSocket server, connection manager, client heartbeats, and CLI test client.", table_cell_style),
            Paragraph("Weeks 3 - 4", table_cell_style),
            Paragraph("Member 2", table_cell_style)
        ],
        [
            Paragraph("<b>Phase 3: Flutter UI & QR</b>", table_cell_bold),
            Paragraph("Full reactive Flutter UI (Lobby, Reveal, Clue, Voting, Results) and camera QR scanner.", table_cell_style),
            Paragraph("Weeks 5 - 6", table_cell_style),
            Paragraph("Member 3", table_cell_style)
        ],
        [
            Paragraph("<b>Phase 4: Embedded CPython</b>", table_cell_bold),
            Paragraph("Bundle CPython 3.12 with serious_python, package pure wheels, and test Android builds.", table_cell_style),
            Paragraph("Weeks 7 - 8", table_cell_style),
            Paragraph("Member 2 & 3", table_cell_style)
        ],
        [
            Paragraph("<b>Phase 5: Supervisor & Control</b>", table_cell_bold),
            Paragraph("Loopback control channel on 127.0.0.1:8766, clean socket teardown fix, and HostService.", table_cell_style),
            Paragraph("Weeks 9 - 10", table_cell_style),
            Paragraph("Member 2 & 3", table_cell_style)
        ],
        [
            Paragraph("<b>Phase 6: Hardening & Testing</b>", table_cell_bold),
            Paragraph("Comprehensive testing (54 pytest, 28 flutter), zero lint issues, and multi-phone trials.", table_cell_style),
            Paragraph("Weeks 11 - 12", table_cell_style),
            Paragraph("All Members", table_cell_style)
        ]
    ]
    t_phases = Table(phases_data, colWidths=[130, 255, 75, 80])
    t_phases.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), SECONDARY),
        ('BOX', (0,0), (-1,-1), 0.75, BORDER_COLOR),
        ('INNERGRID', (0,0), (-1,-1), 0.5, BORDER_COLOR),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, LIGHT_BG]),
        ('TOPPADDING', (0,0), (-1,-1), 2.5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 2.5),
        ('LEFTPADDING', (0,0), (-1,-1), 5),
        ('RIGHTPADDING', (0,0), (-1,-1), 5),
    ]))
    story.append(t_phases)
    story.append(Spacer(1, 5))

    # 7. Risk Assessment & Mitigation
    story.append(Paragraph("7. Risk Analysis & Engineering Mitigation Strategies", h1_style))

    risk_data = [
        [
            Paragraph("Identified Technical Risk", table_header_style),
            Paragraph("Impact", table_header_style),
            Paragraph("Engineered Architectural Mitigation Strategy", table_header_style)
        ],
        [
            Paragraph("<b>CPython Process Singleton</b><br/>CPython cannot be re-initialized once loaded into the process.", table_cell_bold),
            Paragraph("<font color='#C53030'><b>HIGH</b></font>", table_cell_style),
            Paragraph("Architected a persistent in-process supervisor running on local loopback; servers start/stop dynamically via socket commands without killing the CPython runtime.", table_cell_style)
        ],
        [
            Paragraph("<b>Android OS Process Throttling</b><br/>OEM battery managers suspend sockets when screen dims.", table_cell_bold),
            Paragraph("<font color='#DD6B20'><b>MED</b></font>", table_cell_style),
            Paragraph("Configured Android 14 <code>specialUse</code> Foreground Service with ongoing notification drawer icon and partial CPU wake locks.", table_cell_style)
        ],
        [
            Paragraph("<b>Wi-Fi AP Isolation in Public Venues</b><br/>Public routers block direct peer-to-peer packets.", table_cell_bold),
            Paragraph("<font color='#DD6B20'><b>MED</b></font>", table_cell_style),
            Paragraph("Implemented multi-interface fallback parser allowing the host phone to enable Portable Hotspot, creating an isolated private subnet for peer clients.", table_cell_style)
        ]
    ]
    t_risk = Table(risk_data, colWidths=[160, 50, 330])
    t_risk.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,0), PRIMARY),
        ('BOX', (0,0), (-1,-1), 0.75, BORDER_COLOR),
        ('INNERGRID', (0,0), (-1,-1), 0.5, BORDER_COLOR),
        ('ROWBACKGROUNDS', (0,1), (-1,-1), [colors.white, LIGHT_BG]),
        ('TOPPADDING', (0,0), (-1,-1), 2.5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 2.5),
        ('LEFTPADDING', (0,0), (-1,-1), 5),
        ('RIGHTPADDING', (0,0), (-1,-1), 5),
    ]))
    story.append(t_risk)
    story.append(Spacer(1, 5))

    # 8. Success & Acceptance Criteria
    story.append(Paragraph("8. Success Metrics & Final Acceptance Criteria", h1_style))
    story.append(Paragraph(
        "• <b>Zero-Cloud Verification:</b> Full 3+ player games successfully played on airplane mode with Wi-Fi/Hotspot only, with laptop/cloud servers completely powered off.<br/>"
        "• <b>Clean Port Management:</b> Host exiting a room immediately releases port 8765, verified via <code>adb shell netstat</code>; new rooms start immediately.<br/>"
        "• <b>High Code Quality:</b> 100% test pass rate (54 pytest test cases under Python 3.12, 28 Flutter test cases) with 0 analyzer lints.",
        body_style
    ))

    # Build Document
    doc.build(story, canvasmaker=NumberedCanvas)
    print(f"Project Proposal successfully generated at: {os.path.abspath(output_filename)}")

if __name__ == '__main__':
    target_path = sys.argv[1] if len(sys.argv) > 1 else "PROJECT_PROPOSAL.pdf"
    create_proposal_pdf(target_path)
