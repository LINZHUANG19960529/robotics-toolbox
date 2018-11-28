% Teste unterschiedliche Transformationsfunktionen für Euler-Winkel
% Nutze alle möglichen Kombinationen für Euler-Winkel
%
% Literatur
% [Rob1] Skript Robotik 1

% Moritz Schappler, moritz.schappler@imes.uni-hannover.de, 2018-10
% (C) Institut für mechatronische Systeme, Leibniz Universität Hannover

%% Init
clc
clear

%% Alle Euler-Winkel-Kombinationen durchgehen
N = 12;
zlr = 0;
axes_comb = NaN(N,3);
xyzstrings = {'x', 'y', 'z'};
eulstrings = cell(1,12);
for i = 1:3
  for j = 1:3
    for k = 1:3
      if i == j || j == k
        continue
      end
      zlr = zlr + 1;
      axes_comb(zlr,:) = [i,j,k];
      eulstrings{zlr} = [xyzstrings{i}, xyzstrings{j}, xyzstrings{k}];
    end
  end
end

for i_conv = uint8(1:N)
  eulstr = eulstrings{i_conv};
  
  %% zufällige Rotationsmatrizen generieren (mit passender Konvention)
  n = 10000;
  phi_ges = (0.5-rand(n,3))*pi;
  R_ges = NaN(3,3,n);

  for i = 1:n
    phi_i = phi_ges(i,:)';
    R_ges(:,:,i) = eye(3);
    for j = 1:3
      ax = axes_comb(i_conv,j);
      if ax == 1
        R_ges(:,:,i) = R_ges(:,:,i) * rotx(phi_i(j));
      elseif ax == 2
        R_ges(:,:,i) = R_ges(:,:,i) * roty(phi_i(j));
      elseif ax == 3
        R_ges(:,:,i) = R_ges(:,:,i) * rotz(phi_i(j));
      end
    end
  end
  
  %% Teste eul2r
  for i = 1:n
    phi_i = phi_ges(i,:)';
    R_i = R_ges(:,:,i);
    R_sym = eul2r(phi_i, i_conv);
    if any(abs(R_sym(:) - R_i(:)) > 1e-10)
      error('symbolisch generierte Funktion stimmt nicht');
    end
  end

  %% Teste r2eul
  for i = 1:n
    R_i = R_ges(:,:,i);
    phi_i = r2eul(R_i, i_conv);
    R_i_test = eul2r(phi_i, i_conv);

    if any( abs( R_i(:)-R_i_test(:) ) > 1e-10 )
      error('Umrechnung r2eul%s stimmt nicht', eulstr);
    end
  end
  fprintf('%d Umrechnungen mit r2eul%s getestet\n', n, eulstr);
  
  %% Aufruf der Gradientenmatrizen zwischen Rotationsmatrizen und Euler-Winkeln
  for i = 1:n
    R_i = R_ges(:,:,i);
    phi_i = r2eul(R_i, i_conv);
    % Beide Gradienten berechnen
    dphi_dr = eul_diff_rotmat(R_i, i_conv);
    dr_dphi = rotmat_diff_eul(phi_i, i_conv);
    % Die Multiplikation der Gradienten muss eins ergeben
    % (Differentiale kürzen sich weg)
    test = dphi_dr*dr_dphi - eye(3);
    if any(abs(test(:))>1e-10)
      error('Gradientenmatrizen eul%s_diff_rotmat und rotmat_diff_eul%s stimmen nicht überein', eulstr, eulstr);
    end    
  end
  fprintf('%d Gradientenmatrizen eul%s_diff_rotmat und rotmat_diff_eul%s getestet\n', n, eulstr, eulstr);
  
  %% Testen der Transformationsmatrizen euljac und euljacD bzgl der Zeitableitungen
  % Test: euljac, euljacD
  for i = 1:n
    % erste Orientierung zufällig vorgeben
    R_1 = R_ges(:,:,i);
    phi_1 = r2eul(R_1, i_conv); % Euler-Winkel-Darstellung der 1. Orientierung
    
    % Zufällige infinitesimale Änderung der Orientierung führt zur 2.
    % Orientierung
    delta_phi = rand(3,1)*1e-8;
    phi_2 = phi_1 + delta_phi;
    R_2 = eul2r(phi_2, i_conv); % Darstellung der 2. Orientierung als Rotationsmatrix
    % Orientierungsänderung als Geschwindigkeit darstellen
    delta_t = 1e-8;
    phiD = delta_phi / delta_t;
    % Zeitableitung der Rotationsmatrix aus Differenzenquotienten
    delta_R = R_2 - R_1;
    RD = delta_R / delta_t;
    % Winkelgeschwindigkeit aus Euler-Winkel-Zeitableitung
    omega_tilde = RD * R_1'; % [Rob1], Gl. 7.4 (Eulersche Differentiationsregel)
    omega = vex(omega_tilde);
    
    % Berechnung der Winkelgeschwindigkeit auf zweitem Weg über die
    % Transformationsmatrix der Euler-Winkel
    J = euljac(phi_1, i_conv);
    omega_test = J * phiD;
    
    % Vergleiche, ob Winkelgeschwindigkeit auf beiden Wegen gleich ist
    test = omega_test -omega;
    if any(abs(test(:))>1e-7)
      error('Transformationsmatrix eul%sjac stimmt nicht mit r2eul/eul2r überein', eulstr);
    end    
    
    % Bestimme die Euler-Transformationsmatrix für die beiden infinitesimal
    % voneinander entfernten Orientierungen von vorher
    J1 = euljac(phi_1, i_conv);
    J2 = euljac(phi_2, i_conv);
    % Bestimme die Zeitableitung der Transformationsmatrix aus der
    % Geschwindigkeit von oben
    JD = euljacD(phi_1, phiD, i_conv);
    % Alternative Berechnung der Zeitableitung aus Differenzenquotienten
    JD_test = (J2-J1) / delta_t;
    % Vergleich ob beide Lösungen übereinstimmen und damit  ob die
    % symbolische  Herleitung in euljacD stimmt
    test = JD_test -JD;
    if any(abs(test(:))>1e-7)
      error('Transformationsmatrix eul%sjacD stimmt nicht mit euljac überein', eulstr);
    end 
  end
  fprintf('%d Transformationsmatrizen eul%sjac und eul%sjacD getestet\n', n, eulstr, eulstr);
end