% Ableitung der xyz-Euler-Winkel nach der daraus berechneten Rotationsmatrix
% Konvention: R = rotx(phi1) * roty(phi2) * rotz(phi3).
% (mitgedrehte Euler-Winkel; intrinsisch)
%
% Eingabe:
% R [3x3]:
%   Rotationsmatrix
%
% Ausgabe:
% GradMat [3x9]:
%   Gradientenmatrix: Ableitung der Euler-Winkel nach der (spaltenweise gestapelten) Rotationsmatrix

% Moritz Schappler, moritz.schappler@imes.uni-hannover.de, 2018-10
% (C) Institut für mechatronische Systeme, Leibniz Universität Hannover

function GradMat = eulxyz_diff_rotmat(R)
%% Init
%#codegen
%$cgargs {zeros(3,3)}
assert(isreal(R) && all(size(R) == [3 3]), 'eulxyz_diff_rotmat: R has to be [3x3] (double)');
r11=R(1,1);r12=R(1,2);r13=R(1,3);
r21=R(2,1);r22=R(2,2);r23=R(2,3); %#ok<NASGU>
r31=R(3,1);r32=R(3,2);r33=R(3,3); %#ok<NASGU>
%% Berechnung
% aus codeexport/eulxyz_diff_rotmat_matlab.m (euler_angle_calculations.mw)
t130 = r23 ^ 2 + r33 ^ 2;
t131 = sqrt(t130);
t132 = r13 / t131;
t129 = 0.1e1 / (r11 ^ 2 + r12 ^ 2);
t128 = 0.1e1 / t130;
t1 = [0 0 0 0 0 0 0 -r33 * t128 r23 * t128; 0 0 0 0 0 0 t131 -r23 * t132 -r33 * t132; r12 * t129 0 0 -r11 * t129 0 0 0 0 0;];
GradMat = t1;
