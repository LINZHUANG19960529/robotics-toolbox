% Inverse Kinematik für allgemeinen Roboter (Komplette Trajektorie)
% Allgemeine, stark parametrierbare Funktion zum Aufruf mit allen möglichen
% Einstellungen
% Iterative Lösung der inversen Kinematik mit inverser Jacobi-Matrix
% Zusätzlich Nutzung der differentiellen Kinematik für schnellere Konvergenz
% 
% Eingabe:
% XE
%   Trajektorie von EE-Lagen (Sollwerte)
% XDE
%   Trajektorie von EE-Geschwindigkeiten (Sollwerte)
%   (Die Orientierung wird durch Euler-Winkel-Zeitableitung dargestellt)
% XDDE
%   Trajektorie von EE-Beschleunigungen (Sollwerte)
%   Orientierung bezogen auf Euler-Winkel
% T
%   Zeitbasis der Trajektorie (Alle Zeit-Stützstellen)
% q0
%   Anfangs-Gelenkwinkel für Algorithmus
% s
%   Struktur mit Eingabedaten. Felder, siehe Quelltext.
% 
% Ausgabe:
% Q
%   Trajektorie von Gelenkpositionen (Lösung der IK)
% QD
%   Trajektorie von Gelenkgeschwindigkeiten
% QDD
%   Trajektorie von Gelenkbeschleunigungen
% Jinv_ges
%   Inverse PKM-Jacobi-Matrix für alle Bahnpunkte (spaltenweise in Zeile)
%   (Jacobi zwischen allen Gelenkgeschwindigkeiten qD und EE-geschwindigkeit xDE)
%   (Nicht: Nur Bezug zu Antriebsgeschwindigkeiten qaD)
% JinvD_ges
%   Zeitableitung von Jinv_ges
% JointPos_all
%   gestapelte Positionen aller Gelenke der PKM für alle Zeitschritte
%   (Entspricht letzter Spalte aller Transformationsmatrizen aus fkine_legs)
%   Reihenfolge: Siehe Ausgabe Tc_stack_PKM aus invkin_ser
%   * PKM-Basis
%   * Für jede Beinkette: Basis und alle bewegten Körper-KS. Ohne
%     virtuelles EE-KS
%   * Kein Plattform-KS
% 
% Siehe auch: SerRob/invkin_traj bzw. SerRob/invkin2_traj

% TODO: Nullraumbewegung mit Nebenbedingung
% TODO: Erfolg der IK prüfen

% Quelle:
% [2] Aufzeichnungen Schappler vom 11.12.2018
% [3] Aufzeichnungen Schappler vom 06.07.2020

% Moritz Schappler, moritz.schappler@imes.uni-hannover.de, 2019-02
% (C) Institut für Mechatronische Systeme, Leibniz Universität Hannover

function [Q, QD, QDD, Phi, Jinv_ges, JinvD_ges, JointPos_all] = invkin_traj(Rob, X, XD, XDD, T, q0, s)

s_std = struct( ...
  'I_EE', Rob.I_EE_Task, ... % FG für die IK
  'simplify_acc', false, ... % Berechnung der Beschleunigung vereinfachen
  'mode_IK', 1, ...  % 1=Seriell, 2=PKM
  'wn', zeros(4,1), ... % Gewichtung der Nebenbedingung. Standard: Ohne
  'debug', false); % Zusätzliche Ausgabe
if nargin < 7
  % Keine Einstellungen übergeben. Standard-Einstellungen
  s = s_std;
end
% Prüfe Felder der Einstellungs-Struktur und setze Standard-Werte, falls
% Eingabe nicht gesetzt
for f = fields(s_std)'
  if ~isfield(s, f{1})
    s.(f{1}) = s_std.(f{1});
  end
end
dof_3T2R = false;
mode_IK = s.mode_IK;

I_EE = Rob.I_EE_Task;
if all(s.I_EE == logical([1 1 1 1 1 0]))
  dof_3T2R = true;
  I_EE = s.I_EE;
end


if nargout == 6
  % Wenn Jacobi-Zeitableitung als Ausgabe gefordert ist, kann die
  % vollständige Formel für die Beschleunigung benutzt werden
  simplify_acc = false;
else
  % Benutze vollständige Formel entsprechend Einstellungsparameter
  simplify_acc = s.simplify_acc;
end

nt = length(T);


Q = NaN(nt, Rob.NJ);
QD = Q;
QDD = Q;
Phi = NaN(nt, length(Rob.I_constr_t_red)+length(Rob.I_constr_r_red));
% Hier werden die strukturellen FG des Roboters benutzt und nicht die
% Aufgaben-FG. Ist besonders für 3T2R relevant. Hier ist die Jacobi-Matrix
% bezogen auf die FG der Plattform ohne Bezug zur Aufgabe.
Jinv_ges = NaN(nt, sum(Rob.I_EE)*Rob.NJ);
JinvD_ges = zeros(nt, sum(Rob.I_EE)*Rob.NJ);
% Zählung in Rob.NL: Starrkörper der Beinketten, Gestell und Plattform. 
% Hier werden nur die Basis-KS der Beinketten und alle bewegten Körper-KS
% der Beine angegeben.
JointPos_all = NaN(nt, (1+Rob.NL-2+Rob.NLEG)*3);

qk0 = q0;
qDk0 = zeros(Rob.NJ,1);
% Eingabe s_inv3 struktuieren
s_inv3= struct(...
  'K', 0.6*ones(Rob.NJ,1), ... % Verstärkung
  'Kn', 0*ones(Rob.NJ,1), ... % Verstärkung ... hat keine Wirkung
  'wn', zeros(2,1), ... % Gewichtung der Nebenbedingung
  'maxstep_ns', 0*ones(Rob.NJ,1), ... % hat keine Wirkung
  'normalize', true, ...
  'n_min', 0, ... % Minimale Anzahl Iterationen
  'n_max', 1000, ... % Maximale Anzahl Iterationen
  'scale_lim', 1, ... % Herunterskalierung bei Grenzüberschreitung
  'Phit_tol', 1e-9, ... % Toleranz für translatorischen Fehler
  'Phir_tol', 1e-9,... % Toleranz für rotatorischen Fehler
  'maxrelstep', 0.1, ... % Maximale Schrittweite relativ zu Grenzen
  'maxrelstep_ns', 0.005, ... % hat keine Wirkung
  'retry_limit', 100);
for f = fields(s_inv3)'
  if isfield(s, f{1})
    s_inv3.(f{1}) = s.(f{1});
  end
end

% Eingabe s_ser struktuieren
s_ser = struct(...
  'reci', false, ...
  'K', 0.5*ones(Rob.NJ,1), ... % Verstärkung
  'Kn', 0*ones(Rob.NJ,1), ... % hat keine Wirkung
  'wn', zeros(2,1), ... % Gewichtung der Nebenbedingung
  'scale_lim', 0.0, ... % Herunterskalierung bei Grenzüberschreitung
  'maxrelstep', 0.05, ... % Maximale auf Grenzen bezogene Schrittweite
  'normalize', true, ... % Normalisieren auf +/- 180°
  'n_min', 0, ... % Minimale Anzahl Iterationen
  'n_max', 1000, ... % Maximale Anzahl Iterationen
  'rng_seed', NaN, ... Initialwert für Zufallszahlengenerierung
  'Phit_tol', 1e-9, ... % Toleranz für translatorischen Fehler
  'Phir_tol', 1e-9, ... % Toleranz für rotatorischen Fehler
  'retry_limit', 100);
for f = fields(s_ser)'
  if isfield(s, f{1})
    s_ser.(f{1}) = s.(f{1});
  end
end
% keine Nullraum-Optim. bei IK-Berechnung auf Positionsebene
s_ser.wn = zeros(2,1);
s_inv3.wn = zeros(2,1);
qlim = cat(1, Rob.Leg.qlim);
qDlim = cat(1, Rob.Leg.qDlim);
if ~all(isnan(qDlim(:)))
  limits_qD_set = true;
  qDmin = qDlim(:,1);
  qDmax = qDlim(:,2);
else
  limits_qD_set = false;
  qDmin = -inf(Rob.NJ,1);
  qDmax =  inf(Rob.NJ,1);
end
wn = s.wn;
if any(wn ~= 0)
  nsoptim = true;
else
  % Keine zusätzlichen Optimierungskriterien
  nsoptim = false;
end
% Vergleiche FG der Aufgabe und FG des Roboters
if ~dof_3T2R
  % TODO: Hier noch echte Prüfung der FG des Roboters oder detailliertere
  % Fallunterscheidungen notwendig.
  nsoptim = false;
  % Deaktiviere limits_qD_set, wenn es keinen Nullraum gibt
  limits_qD_set = false;
end
% Altwerte für die Bildung des Differenzenquotienten initialisieren
J_x_inv_alt = zeros(Rob.NJ,sum(Rob.I_EE));
Phi_q_alt = zeros(length(Rob.I_constr_t_red)+length(Rob.I_constr_r_red), Rob.NJ);
Phi_x_alt = zeros(length(Rob.I_constr_t_red)+length(Rob.I_constr_r_red), sum(I_EE));

N = eye(Rob.NJ);
for k = 1:nt
  tic();
  x_k = X(k,:)';
  xD_k = XD(k,:)';
  xDD_k = XDD(k,:)';
  if k < nt % Schrittweite für letzten Zeitschritt angenommen wie vorletzter
    dt = T(k+1)-T(k); % Zeit bis zum nächsten Abtastpunkt
  end
  %% Gelenk-Position berechnen
  if mode_IK == 1
    % Aufruf der Einzel-Beinketten-Funktion (etwas schneller, falls mit mex)
    [q_k, Phi_k, Tc_stack_k] = Rob.invkin_ser(x_k, qk0, s_ser);
  else
    % 3T2R-Funktion. Wird hier aber nicht als 3T2R benutzt, da keine
    % Nullraumbewegung ausgeführt wird. Ist nur andere Berechnung.
    [q_k, Phi_k, Tc_stack_k] = Rob.invkin3(x_k, qk0, s_inv3);
  end
  % Abspeichern für Ausgabe.
  Q(k,:) = q_k;
  Phi(k,:) = Phi_k;
  JointPos_all(k,:) = Tc_stack_k(:,4);
  % Prüfe Erfolg der IK
  if any(abs(Phi_k(Rob.I_constr_t_red)) > s_ser.Phit_tol) || ...
     any(abs(Phi_k(Rob.I_constr_r_red)) > s_ser.Phir_tol)
    break; % Die IK kann nicht gelöst werden. Weitere Rechnung ergibt keinen Sinn.
  end
  %% Gelenk-Geschwindigkeit berechnen
  if ~dof_3T2R
    % Benutze die Ableitung der Geschwindigkeits-Zwangsbedingungen
    % (effizienter als Euler-Winkel-Zwangsbedingungen constr1...)
    Phi_q = Rob.constr4grad_q(q_k);
    Phi_x = Rob.constr4grad_x(x_k);
    J_x_inv = -Phi_q \ Phi_x;
  else
    % Nehme vollständige ZB-Gradienten (2. Ausgabe) und wähle Komponenten
    % hier aus. Reduzierte ZB sind noch nicht vollständig implementiert für
    % Systeme mit Beinketten mit fünf Gelenken.
    [Phi_q,Phi_q_voll] = Rob.constr3grad_q(q_k, x_k);
    [~,Phi_x_voll] = Rob.constr3grad_x(q_k, x_k);
    I = Rob.I_constr_red;
    Phi_x=Phi_x_voll(I,I_EE); % TODO: Schon in Funktion richtig machen.
    % Berechne die Jacobi-Matrix basierend auf den vollständigen Zwangsbe-
    % dingungen (wird für Dynamik benutzt).
    J_x_inv = -Phi_q_voll \ Phi_x_voll;
  end
  if ~(nsoptim || limits_qD_set)
    if ~dof_3T2R
      qD_k = J_x_inv * xD_k(I_EE);
    else
      % Bei Aufgabenredundanz ist J_x_inv anders definiert
      qD_k = -Phi_q \ Phi_x * xD_k(I_EE);
    end
  else % Nullraum Optimierung
    % Korrekturterm für Linearisierungsfehler. Für PhiD_pre=0 entsteht die
    % normale inverse differentielle Kinematik. Mit dem Korrekturterm
    % bleibt die Geschwindigkeit konsistent zur Nullraumbewegung aus der
    % Beschleunigung
    PhiD_pre = Phi_q*qDk0;
    PhiD_korr = -PhiD_pre - Phi_x*xD_k(I_EE);
    qD_korr = Phi_q\PhiD_korr;
    qD_k = qDk0 + qD_korr;
    if s.debug % Erneuter Test
      PhiD_test = Phi_x*xD_k(I_EE) + Phi_q*qD_k;
      if any(abs(PhiD_test) > 1e-10)
        error('Korrektur der Geschwindigkeit hat nicht funktioniert');
      end
    end
  end
  %% Gelenk-Beschleunigung berechnen
  if simplify_acc
    if k > 1
      % linksseitiger Differenzenquotient
      JD_x_inv = (J_x_inv-J_x_inv_alt)/(T(k)-T(k-1));
      Phi_qD = (Phi_q - Phi_q_alt)/(T(k)-T(k-1));
    else
      JD_x_inv = zeros(size(J_x_inv_alt));
      Phi_qD = Phi_q_alt; % Mit Null initialisiert
      Phi_xD = Phi_x_alt;
    end
  else
    if ~dof_3T2R
      Phi_qD = Rob.constr4gradD_q(q_k, qD_k);
      Phi_xD = Rob.constr4gradD_x(x_k, xD_k);
      JD_x_inv = Phi_q\(Phi_qD/Phi_q*Phi_x - Phi_xD); % Siehe: ParRob/jacobiD_qa_x
    else
      [Phi_qD,Phi_qD_voll] = Rob.constr3gradD_q(q_k, qD_k, x_k, xD_k);
      [~,Phi_xD_voll] = Rob.constr3gradD_x(q_k, qD_k, x_k, xD_k);
      I = Rob.I_constr_red;
      Phi_xD=Phi_xD_voll(I,I_EE); % TODO: Schon in Funktion richtig machen.
      % Zeitableitung der inversen Jacobi-Matrix konsistent mit obiger
      % Form. Wird für Berechnung der Coriolis-Kräfte benutzt. Bei Kräften
      % spielt die Aufgabenredundanz keine Rolle.
      JD_x_inv = Phi_q_voll\(Phi_qD_voll/Phi_q_voll*Phi_x_voll - Phi_xD_voll);
    end
  end
  if ~dof_3T2R
    qDD_k_T =  J_x_inv * xDD_k(I_EE) + JD_x_inv * xD_k(I_EE); % Gilt nur ohne AR.
  else
    % Direkte Berechnung aus der zweiten Ableitung der Zwangsbedingungen.
    % Siehe [3]. JD_x_inv ist nicht im Fall der Aufgabenredundanz definiert.
    qDD_k_T = -Phi_q\(Phi_qD*qD_k+Phi_xD*xD_k(I_EE)+Phi_x*xDD_k(I_EE));
  end
  if s.debug % Erneuter Test
    PhiDD_test3 = Phi_q*qDD_k_T + Phi_qD*qD_k + ...
      Phi_x*xDD_k(I_EE)+Phi_xD*xD_k(I_EE);
    if any(abs(PhiDD_test3) > 1e-2) % TODO: Unklar, warum z.B. bei Delta-PKM notwendig.
      error('Beschleunigung qDD_k_T erfüllt die kinematischen Bedingungen nicht');
    end
  end
  if nsoptim || limits_qD_set
    N = (eye(Rob.NJ) - pinv(Phi_q)* Phi_q);
  end
  if nsoptim % Nullraumbewegung
    % Berechne Gradienten der zusätzlichen Optimierungskriterien
    v = zeros(Rob.NJ, 1);
    if wn(1) ~= 0
      [~, h1dq] = invkin_optimcrit_limits1(q_k, qlim);
      v = v - wn(1)*h1dq';
    end
    if s.wn(2) ~= 0
      [~, h2dq] = invkin_optimcrit_limits2(q_k, qlim);
      v = v - wn(2)*h2dq';
      if any(isinf(h2dq)), warning('h2dq Inf'); return; end
    end
    if wn(3) ~= 0
      [~, h3dq] = invkin_optimcrit_limits1(qD_k, qDlim);
      v = v - wn(3)*h3dq';
    end
    if wn(4) ~= 0
      [~, h4dq] = invkin_optimcrit_limits2(qD_k, qDlim);
      v = v - wn(4)*h4dq';
    end

    qDD_N_pre = N * v;  
  else
    qDD_N_pre = zeros(Rob.NJ, 1);
  end
  if limits_qD_set
    qDD_pre = qDD_k_T + qDD_N_pre; 
    qD_pre = qD_k + qDD_pre*dt;
    deltaD_ul = (qDmax - qD_pre); % Überschreitung der Maximalwerte: <0
    deltaD_ll = (-qDmin + qD_pre); % Unterschreitung Minimalwerte: <0
    if any([deltaD_ul;deltaD_ll] < 0)
      if min(deltaD_ul)<min(deltaD_ll)
        % Verletzung nach oben ist die größere
        [~,I_worst] = min(deltaD_ul);
        qDD_lim_I = (qDmax(I_worst)-qD_k(I_worst))/dt;% [3]/(3)
      else
        % Verletzung nach unten ist maßgeblich
        [~,I_worst] = min(deltaD_ll);
        qDD_lim_I = (qDmin(I_worst)-qD_k(I_worst))/dt;
      end
      qD_pre_h = qD_pre;
      qD_pre_h(~(deltaD_ll<0|deltaD_ul<0)) = 0; % Nur Reduzierung, falls Grenze verletzt
      [~, hdqD] = invkin_optimcrit_limits1(qD_pre_h, qDlim);
      qDD_N_h = N * (-hdqD');
      % Normiere den Vektor auf den am stärksten grenzverletzenden Eintrag
      qDD_N_he = qDD_N_h/qDD_N_h(I_worst); % [3]/(5)
      % Stelle Nullraumbewegung so ein, dass schlechtester Wert gerade so
      % an der Grenze landet.
      qDD_N_korr_I = -qDD_pre(I_worst) + qDD_lim_I; % [3]/(7)
      % Erzeuge kompletten Vektor als durch Skalierung des Nullraum-Vektors
      qDD_N_korr = qDD_N_korr_I*qDD_N_he; % [3]/(8)
      qDD_N_post = qDD_N_pre+qDD_N_korr; % [3]/(6)
    else
      qDD_N_post = qDD_N_pre;
    end
  else 
    qDD_N_post = qDD_N_pre;
  end
  qDD_k = qDD_k_T + qDD_N_post;
  
  % Teste die Beschleunigung (darf die Zwangsbedingungen nicht verändern)
  if s.debug
    % Das wäre eigentlich gar nicht notwendig, wenn die Beschleunigung
    % eine korrekte Nullraumbewegung ausführt.
    PhiDD_pre = Phi_q*qDD_k + Phi_qD*qD_k;
    PhiDD_korr = -PhiDD_pre - (Phi_x*xDD_k(I_EE)+Phi_xD*xD_k(I_EE));
    if any(abs(PhiDD_korr) > 1e-8)
      error('Beschleunigung ist nicht konsistent nach Nullraumbewegung. Fehler %1.1e', max(abs(PhiDD_korr)));
      % Dieser Teil sollte nicht ausgeführt werden müssen (s.o.)
      qDD_korr = Phi_q\PhiDD_korr; %#ok<UNRCH>
      qDD_k = qDD_k + qDD_korr;
      % Nochmal testen
      PhiDD_test2 = Phi_q*qDD_k + Phi_qD*qD_k + ...
        Phi_x*xDD_k(I_EE)+Phi_xD*xD_k(I_EE);
      if any(abs(PhiDD_test2) > 1e-10)
        error('Korrektur der Beschleunigung hat nicht funktioniert');
      end
    end
  end
  %% Anfangswerte für Positionsberechnung in nächster Iteration
  % Berechne Geschwindigkeit aus Linearisierung für nächsten Zeitschritt
  qDk0 = qD_k + qDD_k*dt;
  % Aus Geschwindigkeit berechneter neuer Winkel für den nächsten Zeitschritt
  % Taylor-Reihe bis 2. Ordnung für Position (Siehe [2])
  qk0 = q_k + qD_k*dt + 0.5*qDD_k*dt^2;
  
  %% Ergebnisse speichern
  QD(k,:) = qD_k;
  QDD(k,:) = qDD_k;
  if nargout >= 5
    Jinv_ges(k,:) = J_x_inv(:);
  end
  if nargout >= 6
    JinvD_ges(k,:) = JD_x_inv(:);
  end
  J_x_inv_alt = J_x_inv;
  Phi_q_alt = Phi_q;
  Phi_x_alt = Phi_x;
end
