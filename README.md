ECUlibre ist ein Open-Source-Projekt, das sich zum Ziel gesetzt hat, freie (libre) Software und Hardware für Motorsteuergeräte (ECUs) zu entwickeln. Sein Hauptziel ist die Reverse-Engineerung und Bereitstellung einer Alternative zu den proprietären Bosch ME7.x-Serie von ECUs, die in Millionen von Fahrzeugen (insbesondere Volkswagen, Audi, Seat und Škoda) von den späten 1990ern bis Mitte der 2000er Jahre verbaut wurden.

Es ist ein Projekt für Enthusiasten, Tuner und Forscher, die volle Transparenz und Kontrolle über ihr Motorsteuerungssystem wollen, weg von geschlossenen, proprietären Tuning-Lösungen.
Wichtige Bestandteile des Projekts

Das Repository enthält mehrere entscheidende Teile:

    Firmware (fw/): Dies ist das Herzstück des Projekts – der tatsächliche C-Code, der auf dem Mikroprozessor der ECU (ein Siemens C167 oder Abkömmling) läuft. Er erledigt alle Echtzeitaufgaben der Motorsteuerung:

        Auslesen von Sensoren (Kurbelwellenposition, Drosselklappe, Lambda-Sonde usw.)

        Berechnung der Kraftstoffeinspritzimpulsbreite und des Zündzeitpunkts

        Regelung der Leerlaufdrehzahl, des Ladedrucks (bei turboaufgeladenen Motoren) und anderer Aktoren.

        Kommunikation über das OBD-II/K-Leitung Diagnoseprotokoll.

    Hardware-Design (hw/): Während sich das Projekt darauf konzentriert, die Software auf vorhandenen ME7.x-ECUs zu ersetzen, enthält dieser Abschnitt wahrscheinlich Schaltpläne, Board-Layouts und Design-Dateien für verwandte Hardware. Dies könnte beinhalten:

        Adapter-Boards zum Flashen der benutzerdefinierten Firmware.

        Designs für eine komplett Open-Hardware-ECU.

        Breakout-Boards für Anbindung und Debugging.

    Werkzeuge (tools/): Eine Sammlung von Utilities, geschrieben in Python und anderen Sprachen, um den Entwicklungs- und Flash-Prozess zu unterstützen. Diese Tools sind essentiell für Aufgaben wie:

        Flashen: Lesen aus und Schreiben in den Flash-Speicher der ECU.

        Debugging: Kommunikation mit der ECU, um Live-Daten und Fehlercodes auszulesen.

        Kalibrierung: Anpassen der Motor-Kennfelder (z.B. für Kraftstoff, Zündung, Ladedruck) ohne die gesamte Firmware neu kompilieren zu müssen.

    Dokumentation (doc/): Dies ist ein kritischer Teil jedes Reverse-Engineering-Projekts. Sie beinhaltet:

        Detaillierte Informationen zur Bosch ME7.x-Hardwarearchitektur.

        Speicherkarten (wo sich bestimmte Funktionen und Variablen im Speicher der ECU befinden).

        Protokollbeschreibungen für die Kommunikation.

        Pinbelegungen und Hardwareinformationen.

Für wen ist das gedacht?

    Automobil-Enthusiasten & Tuner: Personen, die ihre Fahrzeuge mit vollständigem Verständnis und Kontrolle tunen wollen, anstatt vorgefertigte, closed-source Tuning-Boxen oder Dateien zu verwenden.

    Hardware-Hacker & Ingenieure: Personen, die sich für die inneren Abläufe von automotive Embedded Systems und Echtzeitsteuerung interessieren.

    Studenten & Forscher: Diejenigen, die Embedded Systems, Regelungstheorie oder Reverse Engineering studieren, können dies als komplexe, praxisnahe Fallstudie nutzen.

    Die Open-Source-Community: Ein Projekt, das das Recht auf Reparatur, Modifikation und das Verständnis der Technologien, die wir besitzen, fördert.

Wie man anfängt (Eine grobe Anleitung)

Warnung: Das Arbeiten mit einer ECU kann sie bricken (unbrauchbar machen) oder bei falscher Handhabung möglicherweise Ihren Motor beschädigen. Dies ist nur für erfahrene Benutzer.

    Dokumentation lesen: Bevor Sie etwas tun, lesen Sie gründlich die gesamte Dokumentation im doc/-Ordner. Verstehen Sie die Hardware und die Risiken.

    Hardware besorgen: Sie benötigen:

        Eine kompatible Bosch ME7.x ECU (z.B. aus einem VW Golf MK4, Audi TT, etc.).

        Ein Flash-Tool wie ein Galletto 1260 oder andere, von den Projekt-Tools unterstützte Hardware.

        Eine Möglichkeit, sich mit dem Diagnoseport der ECU zu verbinden (z.B. ein K-Leitung/USB-Kabel).

    Toolchain einrichten: Sie benötigen einen Compiler für die C167-Architektur (wie den Keil C166 Compiler), um die Firmware aus dem Quellcode zu bauen.

    Bauen und Flashen: Kompilieren Sie die Firmware und verwenden Sie die mitgelieferten Python-Tools, um sie auf Ihre ECU zu flashen.

    Tunen: Verwenden Sie die Tools, um eine Verbindung zur ECU herzustellen und die Kalibrierungs-Kennfelder anzupassen, um sie an Ihre Motor-Modifikationen anzupassen.

Verhältnis zu ähnlichen Projekten

ECUlibre existiert in einem Ökosystem von Open-Source-ECU-Projekten:

    Speeduino / FreeEMS: Dies sind Projekte zum Bau von ECUs von Grund auf auf Arduino- oder ähnlichen Plattformen. ECUlibre unterscheidet sich dadurch, dass es spezifisch darauf abzielt, die Software auf verbreiteter, existierender, hochwertiger OEM-Hardware zu ersetzen.

    RusEFI: Ein weiteres leistungsstarkes Open-Source-ECU-Projekt, das sowohl eigene Hardware als auch die Anpassung an einige OEM-ECUs unterstützt. Es und ECUlibre haben ähnliche Ziele, aber unterschiedliche Zielplattformen.

Schlussfolgerung

Das ECUlibre GitHub-Repository ist ein umfassendes und technisch anspruchsvolles Projekt für jeden, der sich für Open-Source-Motorsteuerung interessiert. Es bietet alles von der Low-Level-Firmware bis zu den High-Level-Tools, die needed sind, um die volle Kontrolle über eine Bosch ME7.x ECU zu übernehmen. Es stellt eine bedeutende Leistung im Reverse Engineering dar und verkörpert die Prinzipien von offenem Wissen und dem Recht auf Modifikation.



**ECUlibre** is an open-source project aimed at creating free (libre) software and hardware for Engine Control Units (ECUs). Its primary goal is to reverse-engineer and provide an alternative to the proprietary Bosch ME7.x series of ECUs, which were used in millions of vehicles (especially Volkswagens, Audis, Seats, and Škodas) from the late 1990s to the mid-2000s.

It's a project for enthusiasts, tuners, and researchers who want full transparency and control over their engine management system, moving away from closed, proprietary tuning solutions.

### Key Components of the Project

The repository contains several crucial parts:

1.  **Firmware (`fw/`)**: This is the heart of the project—the actual C code that runs on the ECU's microprocessor (a Siemens C167 or derivative). It handles all the real-time tasks of engine management:
    *   Reading sensors (crankshaft position, throttle, oxygen, etc.)
    *   Calculating fuel injection pulse width and ignition timing
    *   Controlling idle speed, boost (in turbocharged engines), and other actuators.
    *   Communicating over the OBD-II/K-Line diagnostic protocol.

2.  **Hardware Design (`hw/`)**: While the project focuses on replacing the software on existing ME7.x ECUs, this section likely contains schematics, board layouts, and design files for related hardware. This could include:
    *   Adapter boards for flashing the custom firmware.
    *   Designs for a completely open-hardware ECU.
    *   Breakout boards for interfacing and debugging.

3.  **Tools (`tools/`)**: A collection of utilities written in Python and other languages to support the development and flashing process. These tools are essential for tasks like:
    *   **Flashing:** Reading from and writing to the ECU's flash memory.
    *   **Debugging:** Communicating with the ECU to read live data and error codes.
    *   **Calibration:** Modifying the engine maps (e.g., fuel, ignition, boost) without recompiling the entire firmware.

4.  **Documentation (`doc/`)**: This is a critical part of any reverse-engineering project. It includes:
    *   Detailed information on the Bosch ME7.x hardware architecture.
    *   Memory maps (where specific functions and variables are located in the ECU's memory).
    *   Protocol descriptions for communication.
    *   Pinouts and hardware information.

### Who is this for?

*   **Automotive Enthusiasts & Tuners:** People who want to tune their vehicles with complete understanding and control, rather than using off-the-shelf, closed-source tuning boxes or files.
*   **Hardware Hackers & Engineers:** Individuals interested in the inner workings of automotive embedded systems and real-time control.
*   **Students & Researchers:** Those studying embedded systems, control theory, or reverse engineering can use this as a complex, real-world case study.
*   **The Open-Source Community:** A project that champions the right to repair, modify, and understand the technology we own.

### How to Get Started (A Rough Guide)

**Warning:** Working with an ECU can brick it (render it unusable) or potentially damage your engine if done incorrectly. This is for experienced users only.

1.  **Read the Documentation:** Before you do anything, thoroughly read all the documentation in the `doc/` folder. Understand the hardware and the risks.
2.  **Gather Hardware:** You will need:
    *   A compatible Bosch ME7.x ECU (e.g., from a VW Golf MK4, Audi TT, etc.).
    *   A flashing tool like a **Galletto 1260** or other hardware supported by the project's tools.
    *   A way to connect to the ECU's diagnostic port (e.g., a K-Line/USB cable).
3.  **Set Up the Toolchain:** You need a compiler for the C167 architecture (like the Keil C166 compiler) to build the firmware from source.
4.  **Build and Flash:** Compile the firmware and use the provided Python tools to flash it onto your ECU.
5.  **Tune:** Use the tools to connect to the ECU and modify calibration maps to suit your engine modifications.

### Relation to Similar Projects

ECUlibre exists in a ecosystem of open-source ECU projects:
*   **Speeduino / FreeEMS:** These are projects for building ECUs from scratch on Arduino or similar platforms. ECUlibre is different because it specifically targets *replacing the software on widespread, existing, high-quality OEM hardware*.
*   **RusEFI:** Another powerful open-source ECU project, which supports both custom hardware and adapting to some OEM ECUs. It and ECUlibre share similar goals but have different target platforms.

### Conclusion

The ECUlibre GitHub repository is a comprehensive and technically advanced project for anyone interested in open-source engine management. It provides everything from the low-level firmware to the high-level tools needed to take full control of a Bosch ME7.x ECU. It represents a significant achievement in reverse engineering and embodies the principles of open knowledge and the right to modify.
