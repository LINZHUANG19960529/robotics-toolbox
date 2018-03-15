% Transformation zwischen Winkelgeschwindigkeit und Ableitung der
% Orientierungsdarstellung für RPY-Winkel (=XYZ-Euler-Winkel).
% 
% Eingabe:
% phi [3x1]
%   Euler-Winkel alpha, beta, gamma für XYZ-Darstellung
% phiD [3x1]
%   Zeitableitung der Euler-Winkel
% 
% Ausgabe:
% TD
%   Zeitableitung der Transformationsmatrix (3x3) zwischen Winkelgeschwindigkeit im
%   Basiskoordinatensystem und den Zeitableitungen der
%   Rotationsdarstellungen
% 
% Source:
% [1] Natale 2003: Interaction Control of Robot Manipulators:
% Six-Degrees-of-Freedom Tasks 
% [2] Ortmaier: Robotik I Skript WS 2014/15
% [3] Corke: Robotics Toolbox

% Moritz Schappler, schappler@irt.uni-hannover.de, 2015-08
% (c) Institut für Regelungstechnik, Universität Hannover

function TD = angvelotrans_rpyD(phi, phiD)
%% Init
%#codegen
assert( isa(phi,'double') &&  isreal(phi) &&  all(size(phi) == [3 1]) , ...
  'angvelotrans_rpyD:phi has to be 3x1 double');  
assert( isa(phiD,'double') && isreal(phiD) && all(size(phiD) == [3 1]), ...
  'angvelotrans_rpyD:phiD has to be 3x1 double');  

alpha = phi(1);
beta = phi(2);

alphaD = phiD(1);
betaD = phiD(2);

%% Calculation
% Zeitableitung des Terms in angvelotrans_rpy
% Siehe maple_codegen/rotation_rpy_omega.mw
TD = [0, 0,          cos(beta)*betaD;
     0, -sin(alpha)*alphaD, (-cos(alpha)*cos(beta))*alphaD+(-sin(alpha)*(-sin(beta)))*betaD;
     0, cos(alpha)*alphaD, (-sin(alpha)*cos(beta))*alphaD + (cos(alpha)*(-sin(beta)))*betaD];
