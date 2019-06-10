% Roboterklasse für 6UPS-PKM testen
% 
% Ablauf:
% * Beispiel-Parameter und Roboter definieren
% * Gelenkwinkel einstellen: Sollen ungefähr Null sein in der Startpose
% * Jacobi-Beispiel für 3T2R-Jacobi
% * Beispieltrajektorie definieren und berechnen
% * Auswertung
% 
% Beispielsystem: Basis-Kreis 0.5, Plattform-Kreis 0.2

% Moritz Schappler, moritz.schappler@imes.uni-hannover.de, 2019-06
% (C) Institut für Mechatronische Systeme, Universität Hannover

clear
clc

%% Definitionen, Benutzereingaben
% Robotermodell entweder aus PKM-Bibliothek oder nur aus
% Seriell-Roboter-Bibliothek laden. Stellt keinen Unterschied dar.
use_parrob = false;
short_traj = false;

rob_path = fileparts(which('robotics_toolbox_path_init.m'));
respath = fullfile(rob_path, 'examples_tests', 'results');

I_EE_3T3R = logical([1 1 1 1 1 1]);
I_EE_3T2R = logical([1 1 1 1 1 0]);
%% Klasse für PKM erstellen (basierend auf serieller Beinkette)
if isempty(which('serroblib_path_init.m'))
  warning('Repo mit seriellen Robotermodellen ist nicht im Pfad. Beispiel nicht ausführbar.');
  return
end
if ~use_parrob
  % Typ des seriellen Roboters auswählen (S6RRPRRRV3 = UPS)
  SName='S6RRPRRR14V3';
  % Instanz der Roboterklasse erstellen
  RS = serroblib_create_robot_class(SName);
  RS.fill_fcn_handles(true, true); % kompilierte Funktionen verwenden
  % RS.mex_dep(true)
  RP = ParRob('P6RRPRRR14V3A1');
  RP = RP.create_symmetric_robot(6, RS, 0.5, 0.2);
  RP.initialize();
  % Schubgelenke sind aktuiert
  I_qa = false(36,1);
  I_qa(3:6:36) = true;
  RP.update_actuation(I_qa);
  % Benutze PKM-Bibliothek für gespeicherte Funktionen
  if ~isempty(which('parroblib_path_init.m'))
    parroblib_addtopath({'P6RRPRRR14V3A1'});
  end
  RP.fill_fcn_handles();
end
%% Alternativ: Klasse für PKM erstellen (basierend auf PKM-Bibliothek)
if use_parrob
  if isempty(which('parroblib_path_init.m'))
    warning('Repo mit parallelen Robotermodellen ist nicht im Pfad. Beispiel nicht ausführbar.');
    return
  end
  RP = parroblib_create_robot_class('P6RRPRRR14V3A1', 0.5, 0.2);
end

%% Startpose bestimmen
% Mittelstellung im Arbeitsraum
X0 = [ [0;0;0.5]; [0;0;0]*pi/180 ];
for i = 1:10 % Mehrere Versuche für "gute" Pose
  % Startwerte gleichmäßig um Null verteilen, für die Winkelnormalisierung
  q0 = -0.5+rand(36,1); % Startwerte für numerische IK
  q0(RP.I_qa) = 0.4; % mit Schubaktor größer Null anfangen (damit Konfiguration nicht umklappt)

  % Inverse Kinematik auf zwei Arten berechnen
  [~, Phi] = RP.invkin1(X0, q0);
  if any(abs(Phi) > 1e-8)
    error('Inverse Kinematik konnte in Startpose nicht berechnet werden');
  end
  s_init = struct('normalize', true);
  [qs1, Phis] = RP.invkin_ser(X0, rand(36,1), s_init);
  if any(abs(Phis) > 1e-6)
    error('Inverse Kinematik (für jedes Bein einzeln) konnte in Startpose nicht berechnet werden');
  end
  % Nehme nur die normale Konfiguration, nicht die umgeklappte
  if any(qs1(RP.I_qa) < 0)
    if i == 10
      error('Start-Konfiguration ist umgeklappt. Nochmal machen.');
    else
      continue;
    end
  else
    break;
  end
end
%% Wähle willkürlichen Winkel-Offset für Beinketten-Koppel-KS
% Gelenkkoordinaten sollen möglichst um die Null sein, um die
% Winkel-Normalisierung zu vereinfachen
% Benutze die zusätzliche Transformation am Endeffektor der einzelnen
T_0_E = RP.x2t(X0);
qs = qs1;
disp('Gelenkwinkel der Kardangelenke vor Verschiebung der Nullpunkte:');
disp(qs1([1:6:RP.NJ;2:6:RP.NJ])*180/pi);
disp('Gelenkwinkel der Kugelgelenke vor Verschiebung der Nullpunkte:');
disp(qs1([4:6:RP.NJ;5:6:RP.NJ;6:6:RP.NJ])*180/pi);
for i = 1:6
  % Initialisierung (für Mehrfach-Durchführungen)
  RP.Leg(i).update_EE([], zeros(3,1));
  % Gelenkwinkel dieser Beinkette vorbereiten
  qs_i = qs(RP.I1J_LEG(i):RP.I2J_LEG(i));
  % Kugel-Gelenk vorher */150/*. Jetzt */30/*
  % q_spher_fix = qs_i(4:6) - [0;120*pi/180;0];
  q_spher_fix = [0;30;60]*pi/180;
  
  [~,T_0_Pi] = RP.Leg(i).fkineEE(qs_i);
  % Letzte drei Winkel virtuell auf vorgegebenen Wert setzen
  qs_i_test = [qs_i(1:3); q_spher_fix];
  [~,T_0_Pi_test] = RP.Leg(i).fkineEE(qs_i_test);
  % Differenz-Rotation zwischen beiden Fällen als Zusatz-Rotation N-E setzen
  R_N_E = T_0_Pi_test(1:3,1:3)' * T_0_Pi(1:3,1:3);
  RP.Leg(i).update_EE([], r2eul(R_N_E, RP.Leg(i).phiconv_N_E));
  % Start-Winkel anpassen
  qs(RP.I1J_LEG(i)+3:RP.I2J_LEG(i)) = q_spher_fix;
  % % Test: 
  % test = T_0_Pi_test(1:3,1:3)*R_N_E - T_0_E(1:3,1:3);
  % % Kinematik neu berechnen
  % [~,T_0_Pi_test2] = RP.Leg(i).fkineEE(qs_i_test);
  % Gelenkwinkel dieser Beinkette vorbereiten
  qs_i = qs(RP.I1J_LEG(i):RP.I2J_LEG(i));
  % Ändere Beinketten-Basis-KS so, dass auch die Winkel des Kardan-Gelenks
  % Null sind.
  % TODO: Zelle nach Definition des Roboters nur einmal ausführbar
  % Kardan-Gelenk vorher 90/150. Jetzt 30/-30
  % q_univ_fix = qs_i(1:2) - 0*[pi/2; pi];
  q_univ_fix = [30;-30]*pi/180;
  R_0_0i1 = RP.Leg(i).T_W_0(1:3,1:3);
  [~,T_0_Pi] = RP.Leg(i).fkineEE(qs_i);
  % Erste zwei Winkel virtuell Null setzen
  qs_i_test = [q_univ_fix; qs_i(3:6)];
  T_0i_Pi_test = RP.Leg(i).fkineEE(qs_i_test);
  % Differenz-Rotation zwischen beiden Fällen zusätzlich zur Rotations 0i-0
  % hinzufügen
  R_0i1_0i2 = R_0_0i1' * T_0_Pi(1:3,1:3) * T_0i_Pi_test(1:3,1:3)';
  % test = R_0_0i1 * R_0i1_0i2 * T_0i_Pi_test(1:3,1:3) - T_0_Pi(1:3,1:3)
  R_0_0i_neu = R_0_0i1 * R_0i1_0i2;
  RP.Leg(i).update_base([], r2eul(R_0_0i_neu, RP.Leg(i).phiconv_W_0));
  % Start-Winkel anpassen
  qs(RP.I1J_LEG(i):RP.I1J_LEG(i)+1) = q_univ_fix;
end

% Winkel erneut normalisieren
qs(RP.MDH.sigma==0) = normalize_angle(qs(RP.MDH.sigma==0));
disp('Gelenkwinkel der Kardangelenke nach Verschiebung der Nullpunkte:');
disp(qs([1:6:RP.NJ;2:6:RP.NJ])*180/pi);
disp('Gelenkwinkel der Kugelgelenke nach Verschiebung der Nullpunkte:');
disp(qs([4:6:RP.NJ;5:6:RP.NJ;6:6:RP.NJ])*180/pi);
%% Zwangsbedingungen in Startpose testen
RP.update_EE_FG(I_EE_3T3R, I_EE_3T3R);
Phi1=RP.constr1(qs, X0);
Phit1=RP.constr1_trans(qs, X0);
Phir1=RP.constr1_rot(qs, X0);
if any(abs(Phi1) > 1e-6)
  error('ZB in Startpose ungleich Null');
end

%% Roboter in Startpose plotten
figure(1);clf;
hold on;grid on;
xlabel('x [m]');ylabel('y [m]');zlabel('z [m]');
view(3);
s_plot = struct( 'ks_legs', [RP.I1L_LEG; RP.I1L_LEG+1; RP.I2L_LEG], 'straight', 0);
RP.plot( qs, X0, s_plot );

%% Gelenkwinkelgrenzen festlegen (für Optimierung
for i = 1:RP.NLEG
  q_i = qs(RP.I1J_LEG(i):RP.I2J_LEG(i));
  qlim_i = repmat(q_i,1,2);
  % Grenzen um die aktuelle Konfiguration herum wählen
  I1 = RP.Leg(i).MDH.sigma==1;
  % Schubachsen: Maximaler Hub +-500mm
  qlim_i(I1,:) = repmat(q_i(I1),1,2) + repmat([-0.5, 0.5], sum(I1),1);
  I0 = RP.Leg(i).MDH.sigma==0;
  % Kippwinkel der Kardan- und Kugelgelenke max. 60° in jede Richtung
  qlim_i(I0,:) = repmat(q_i(I0),1,2) + repmat([-pi/3, pi/3], sum(I0),1);
  RP.Leg(i).qlim = qlim_i;
end
% qlim für gesamte PKM festlegen
qlim = NaN(RP.NJ,2);
J1 = 1;
for i = 1:RP.NLEG
  J2 = J1+RP.Leg(i).NQJ-1;
  qlim(J1:J2,:) = RP.Leg(i).qlim;
  J1 = J2+1;
end
%% Initialisierung Teil 2
RP.update_EE_FG(I_EE_3T3R, I_EE_3T2R);

%% Jacobi-Matrizen auswerten

G_q_voll = RP.constr3grad_q(qs, X0);
G_x_voll = RP.constr3grad_x(qs, X0);

G_q = G_q_voll(RP.I_constr_red,:);
G_x = G_x_voll(RP.I_constr_red,:);

% Aufteilung der Ableitung nach den Gelenken in Gelenkklassen 
% * aktiv/unabhängig (a),
% * passiv+schnitt/abhängig (d)
G_a = G_q(:,RP.I_qa);
G_d = G_q(:,RP.I_qd);
% Jacobi-Matrix zur Berechnung der abhängigen Gelenke und EE-Koordinaten
G_dx = [G_d, G_x];

fprintf('%s: Rang der vollständigen Jacobi der inversen Kinematik: %d/%d\n', ...
  RP.mdlname, rank(G_q), RP.NJ);
fprintf('%s: Rang der vollständigen Jacobi der direkten Kinematik: %d/%d\n', ...
  RP.mdlname, rank(G_dx), sum(RP.I_EE_Task)+sum(RP.I_qd));
fprintf('%s: Rang der Jacobi der aktiven Gelenke: %d/%d\n', ...
  RP.mdlname, rank(G_a), sum(RP.I_EE_Task));

%% Beispieltrajektorie berechnen und zeichnen
% IK-Grundeinstellungen
s = struct('Phit_tol', 1e-9, 'Phir_tol', 1e-9, ...
  'maxstep_ns', 1e-5, ... % Schrittweite für Nullraum-Inkremente gering halten
  'wn', [0;1], 'K', 7e-1*ones(RP.NJ,1), ...
  'Kn', 0.7*ones(RP.NJ,1), ...
  'scale_lim', 0.7, ...
  'retry_limit', 0, 'I_EE', I_EE_3T2R, ...
  'maxrelstep', 0.25); % Grenzen sind nicht so breit; nehme größere max. Schrittweite

% Trajektorie mit beliebigen Bewegungen der Plattform
XL = [X0'+1*[[ 0.0, 0.0, 0.0], [ 0.0, 0.0, 0.0]]; ...
      X0'+1*[[ 0.0, 0.05, 0.0], [ 0.0, 0.0, 0.0]]; ...
      X0'+1*[[ 0.1, 0.0, 0.0], [ 0.0, 0.0, 0.0]]; ...
      X0'+1*[[ 0.0,-0.1, 0.0], [ 0.0, 0.0, 0.0]]; ...
      X0'+1*[[-0.1, 0.0, 0.0], [ 0.0, 0.0, 0.0]]; ...
      X0'+1*[[ 0.0, 0.05, 0.0], [ 0.0, 0.0, 0.0]]; ...
      X0'+1*[[ 0.2,-0.1, 0.3], [ 0.3, 0.2, 0.1]]; ...
      X0'+1*[[-0.1, 0.1,-0.1], [-0.2,-0.2,-0.2]]; ...
      X0'+1*[[ 0.2,-0.1, 0.2], [ 0.2, 0.1, 0.3]]];
XL = [XL; XL(1,:)]; % Rückfahrt zurück zum Startpunkt.

% Berechne IK zu den einzelnen Eckpunkten. Wenn das nicht geht, bringt die
% Trajektorie sowieso nichts
s_ep = s;
s_ep.wn = [0;1e-3]; % Man kann mehr bis an die Ränder gehen
s.n_max = 5000; % Mehr Versuche (Abstände zwischen Punkten größer)
for i = 1:size(XL,1)
  [q_i, Phi_i] = RP.invkin3(XL(i,:)', qs, s_ep);
  if max(abs(Phi_i)) > 1e-6
    error('Eckpunkt %d geht nicht', i);
  end
  fprintf('Eckpunkt %d berechnet\n', i);
end

[X_t,XD_t,XDD_t,t] = traj_trapez2_multipoint(XL, 1, 0.1, 0.01, 1e-3, 1e-2);
% Debug: Trajektorie reduzieren
if short_traj
  n = 200;
else
  n = length(t);
end
% II = length(t)-n+1:1:length(t);
II = 1:n;
t = t(II);
X_t = X_t(II,:);
XD_t = XD_t(II,:);
XDD_t = XDD_t(II,:);

% Inverse Kinematik berechnen;  Lösung der IK von oben als Startwert
t0 = tic();
s_start = s;
% Toleranz maximal stark setzen, damit es keinen Sprung im Verlauf gibt
% (durch die vielen Nullraumiterationen ist die Aufgabentoleranz später
% sowieso ungefähr Null.
s_start.Phit_tol = 1e-14;
s_start.Phir_tol = 1e-14;
% s_start.normalize = false;
s_start.maxstep_ns = 1e-10; % Nullraumbewegung sollte schon zum Optimum konvergiert sein
% Berechne IK mit 3T2R
RP.update_EE_FG(I_EE_3T3R, I_EE_3T2R);
warning on
[q1, Psi_num1] = RP.invkin3(X_t(1,:)', qs, s);
if any(abs(Psi_num1) > 1e-4)
  warning('IK konvergiert nicht');
end
% Normiere die Start-Gelenkwinkel auf Bereich 0 bis 1
qsnorm = (qs-qlim(:,1)) ./ (qlim(:,2) - qlim(:,1)); % Muss 0.5 sein per Definition 
q1norm = (q1-qlim(:,1)) ./ (qlim(:,2) - qlim(:,1));
if any(abs(q1norm) > 1) || any(abs(q1norm) < 0)
  warning('Anfangs-Konfiguration für Trajektorie verletzt bereits die Grenzen');
end
%% Roboter in Startpose plotten
figure(2);clf;
hold on;grid on;
xlabel('x [m]');ylabel('y [m]');zlabel('z [m]');
view(3);
s_plot = struct( 'ks_legs', [RP.I1L_LEG; RP.I1L_LEG+1; RP.I2L_LEG], 'straight', 0);
RP.plot( q1, X0, s_plot );
plot3(X_t(:,1), X_t(:,2), X_t(:,3));
%% Trajektorie berechnen
% Berechne Beispiel-Trajektorie für 3T2R
% Einstellungen für Trajektorie: Kein Normalisieren, damit Traj. nicht
% springt. Muss doch normalisieren, damit Gelenkwinkelgrenzen korrekt
% erkannt werden.
s_Traj = s;
s_Traj.normalize = false; % Mit Kriterium 2 keine Normalisierung. Sonst können Koordinaten jenseits der Grenzen landen
s_Traj.wn = [0;1];
fprintf('3T2R Inverse Kinematik für Trajektorie berechnen: %d Bahnpunkte\n', length(t));
[Q_t, QD_t, ~, Phi_t] = RP.invkin_traj(X_t, XD_t, XDD_t, t, q1, s_Traj);
if any(any(abs(Phi_t) > max(s.Phit_tol,s.Phir_tol)))
   error('Fehler in Trajektorie zu groß. IK nicht berechenbar');
end

% Berechne Ist-EE-Traj.
X_ist = NaN(n,6*RP.NLEG);
i_BiKS = 1+RP.Leg(1).NL+1;
II_BiKS = i_BiKS:(RP.Leg(1).NL+1):(1+(RP.Leg(1).NL+1)*RP.NLEG);
for i = 1:n
  Tc_ges = RP.fkine(Q_t(i,:)', NaN(6,1));
  % Schnitt-KS aller Beinketten bestimmen
  T_Bi = Tc_ges(:,:,II_BiKS);
  for j = 1:RP.NLEG
    R_0_Bj = T_Bi(1:3,1:3,j);
    r_0_0_Bj = T_Bi(1:3,4,j);
    r_P_P_Bj = RP.r_P_B_all(:,j);
    r_0_Bj_P = -R_0_Bj*r_P_P_Bj;
    r_0_Ej = r_0_0_Bj + r_0_Bj_P;
    if j == 1
      r_0_E_Legs = r_0_Ej;
    elseif any(abs(r_0_E_Legs-r_0_Ej)>2e-6) % muss größer als IK-Toleranz sein
      error('EE aus Beinkette %d stimmt nicht mit Beinkette 1 überein', j);
    end
    T_E_Leg_j = rt2tr(R_0_Bj, r_0_Ej);
    X_ist(i,6*(j-1)+1:6*j) = RP.t2x(T_E_Leg_j);
  end
  R_E_Legs = R_0_Bj;
end

H1_t = NaN(length(t),1+RP.NLEG);
% Gütefunktion nochmal berechnen
for i = 1:length(t)
  H1_t(i,1) = invkin_optimcrit_limits1(Q_t(i,:)', qlim);
  for j = 1:6
    H1_t(i,1+j) = invkin_optimcrit_limits1(Q_t(i,RP.I1J_LEG(j):RP.I2J_LEG(j))', qlim(RP.I1J_LEG(j):RP.I2J_LEG(j),:));
  end
end
% Gelenkkoordinaten normieren
Q_t_norm = (Q_t - repmat(qlim(:,1)',n,1)) ./ repmat(qlim(:,2)'-qlim(:,1)',n,1);

%% Ergebniss speichern
save(fullfile(respath, 'ParRob_class_example_6UPS_3T2R_results.mat'));

%% Zeitverlauf der Trajektorie plotten
% Gesamtbild
figure(4);clf;
subplot(3,2,sprc2no(3,2,1,1)); hold on;
plot(t, X_t);set(gca, 'ColorOrderIndex', 1)
% plot([0;t(end)],[X0';X0'],'o--')
legend({'$x$', '$y$', '$z$', '$\varphi_x$', '$\varphi_y$', '$\varphi_z$'}, 'interpreter', 'latex')
grid on;
ylabel('x_E');
subplot(3,2,sprc2no(3,2,2,1));
plot(t, XD_t);
grid on;
ylabel('xD_E');
subplot(3,2,sprc2no(3,2,3,1));
plot(t, XDD_t);
grid on;
ylabel('xDD_E');
subplot(3,2,sprc2no(3,2,1,2));
plot(t, Q_t);
grid on;
ylabel('Q');
subplot(3,2,sprc2no(3,2,2,2)); hold on;
plot(t, Phi_t(:,RP.I_constr_t_red));
plot(t([1 end]), s.Phit_tol*[1;1], 'r--');
plot(t([1 end]),-s.Phit_tol*[1;1], 'r--');
grid on;
ylabel('\Phi_{trans}');
subplot(3,2,sprc2no(3,2,3,2)); hold on;
plot(t, Phi_t(:,RP.I_constr_r_red));
plot(t([1 end]), s.Phir_tol*[1;1], 'r--');
plot(t([1 end]),-s.Phir_tol*[1;1], 'r--');
grid on;
ylabel('\Phi_{rot}');

figure(5);clf;
plot(t, H1_t);

figure(6);clf;
for i = 1:6
  subplot(3,2,i); hold on
  plot(t, X_ist(:,i:6:end));
  plot(t, X_t(:,i), '--');
  ylabel(sprintf('x %d', i));
end

% Bild für einzelne Beine
figure(7);clf;
for i = 1:RP.NLEG
  % Gelenkkoordinaten
  subplot(4,RP.NLEG,sprc2no(4,RP.NLEG,1,i));
  plot(t, Q_t(:,RP.I1J_LEG(i):RP.I2J_LEG(i)));
  ylabel(sprintf('q_%d', i)); grid on;
  if i == 6
    l = {};
    for j = 1:6
      l = {l{:}, sprintf('q_%d', j)}; %#ok<SAGROW>
    end
    legend(l);
  end

  % Normierte Gelenk-Koordinaten.
  subplot(4,RP.NLEG,sprc2no(4,RP.NLEG,2,i));
  plot(t, Q_t_norm(:,RP.I1J_LEG(i):RP.I2J_LEG(i)));
  ylabel(sprintf('q_%d (norm)', i)); grid on;
  
  % ZB
  subplot(4,RP.NLEG,sprc2no(4,RP.NLEG,3,i));
  plot(t, Phi_t(:,RP.I1constr_red(i):RP.I2constr_red(i)));
  ylabel(sprintf('ZB %d', i)); grid on;
  
  % Zielfunktion
  subplot(4,RP.NLEG,sprc2no(4,RP.NLEG,4,i));
  plot(t, H1_t(:,1+i));
  ylabel(sprintf('Zielfunktion %d', i)); grid on;
end
linkxaxes

return
%% Animation des bewegten Roboters
s_anim = struct( 'gif_name', fullfile(respath, 'ParRob_class_example_6UPS_3T2R.gif'));
s_plot = struct( 'ks_legs', [RP.I1L_LEG; RP.I1L_LEG+1; RP.I2L_LEG], 'straight', 0);
figure(10);clf;hold all;
set(10, 'units','normalized','outerposition',[0 0 1 1]); % Vollbild, damit GIF größer wird
view(3);
axis auto
hold on;grid on;
xlabel('x [m]');ylabel('y [m]');zlabel('z [m]');
RP.anim( Q_t(1:20:size(Q_t,1),:), X_t(1:20:size(X_t,1),:), s_anim, s_plot);
fprintf('Animation der Bewegung gespeichert: %s\n', fullfile(respath, 'ParRob_class_example_6UPS.gif'));
fprintf('Test für 6UPS beendet\n');